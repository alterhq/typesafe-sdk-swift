import XCTest

@testable import TypeSafe

private enum HeaderProviderError: Error, Equatable {
  case signedOut
}

private final class LockedLogCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String] = []

  func append(_ entry: String) {
    lock.withLock { entries.append(entry) }
  }

  func snapshot() -> [String] {
    lock.withLock { entries }
  }
}

private actor RotatingHeaderProvider {
  private var contexts: [AuthenticationContext] = []

  func headers(for context: AuthenticationContext) -> [String: String] {
    contexts.append(context)
    return [
      "Authorization": "Bearer app-token-\(context.attempt)",
      "X-Auth-Attempt": String(context.attempt),
    ]
  }

  func capturedContexts() -> [AuthenticationContext] { contexts }
}

final class AuthenticationTests: XCTestCase {
  func testProxyUsesAppAuthenticationAndPreservesTypedClient() async throws {
    let transport = MockTransport([.response(jsonResponse(modelsJSON))])
    let client = try TypeSafeClient(
      authentication: .bearerToken("alter-jwt"),
      baseURL: "https://api.alter.example/typesafe/",
      logger: .disabled,
      defaultHeaders: ["X-App-Version": "1.2.3"],
      transport: transport
    )

    let models = try await client.models.list(
      options: .init(headers: ["X-Action-Id": "action-123"]))
    XCTAssertEqual(models.first?.name, "jev-latest")
    XCTAssertFalse(client.usesTypeSafeAPIKey)

    let captured = await transport.requests()
    let request = try XCTUnwrap(captured.first)
    XCTAssertEqual(request.url.absoluteString, "https://api.alter.example/typesafe/v1/models")
    XCTAssertEqual(header("Authorization", in: request), "Bearer alter-jwt")
    XCTAssertEqual(header("X-App-Version", in: request), "1.2.3")
    XCTAssertEqual(header("X-Action-Id", in: request), "action-123")
  }

  func testExplicitAuthenticationIgnoresTypeSafeKeyEnvironment() async throws {
    let transport = MockTransport([.response(jsonResponse(modelsJSON))])
    let client = try TypeSafeClient(
      apiKey: nil,
      authentication: .unauthenticated,
      baseURL: "https://proxy.example",
      defaultModel: nil,
      logLevel: nil,
      logger: .disabled,
      retry: nil,
      timeoutMilliseconds: 10_000,
      defaultHeaders: ["X-App-Session": "cookie-authenticated"],
      transport: transport,
      environment: [TypeSafeEnvironment.apiKey: "must-not-leak"]
    )

    _ = try await client.models.list()
    let captured = await transport.requests()
    let request = try XCTUnwrap(captured.first)
    XCTAssertNil(header("Authorization", in: request))
    XCTAssertEqual(header("X-App-Session", in: request), "cookie-authenticated")
    XCTAssertFalse(client.usesTypeSafeAPIKey)
  }

  func testDynamicHeadersAreRefreshedForEveryRetry() async throws {
    let source = RotatingHeaderProvider()
    let transport = MockTransport([
      .response(jsonResponse("{}", status: 503)),
      .response(jsonResponse(modelsJSON)),
    ])
    let retry = try RetryPolicy(
      backoffInitialMilliseconds: 0,
      backoffMaxMilliseconds: 0,
      backoffJitter: 0
    )
    let client = try TypeSafeClient(
      authentication: .headers(sensitiveHeaderNames: ["X-Auth-Attempt"]) { context in
        await source.headers(for: context)
      },
      baseURL: "https://proxy.example/sdk",
      logger: .disabled,
      retry: retry,
      transport: transport
    )

    _ = try await client.models.list()

    let requests = await transport.requests()
    XCTAssertEqual(header("Authorization", in: requests[0]), "Bearer app-token-0")
    XCTAssertEqual(header("Authorization", in: requests[1]), "Bearer app-token-1")
    XCTAssertEqual(header("X-TypeSafe-Retry-Count", in: requests[1]), "1")
    let contexts = await source.capturedContexts()
    XCTAssertEqual(contexts.map(\.attempt), [0, 1])
    XCTAssertEqual(contexts.map(\.method), [.get, .get])
    XCTAssertTrue(contexts.allSatisfy { $0.url.path == "/sdk/v1/models" })
  }

  func testAuthenticationHeadersOverrideCallerHeaders() async throws {
    let transport = MockTransport([.response(jsonResponse(modelsJSON))])
    let client = try TypeSafeClient(
      authentication: .headers(["Authorization": "Bearer provider"]),
      baseURL: "https://proxy.example",
      logger: .disabled,
      defaultHeaders: ["authorization": "Bearer default"],
      transport: transport
    )
    _ = try await client.models.list(
      options: .init(headers: ["AUTHORIZATION": "Bearer request"]))
    let captured = await transport.requests()
    let request = try XCTUnwrap(captured.first)
    XCTAssertEqual(header("Authorization", in: request), "Bearer provider")
  }

  func testHeaderProviderErrorsPropagateUnchanged() async throws {
    let client = try TypeSafeClient(
      authentication: .headers { _ in throw HeaderProviderError.signedOut },
      baseURL: "https://proxy.example",
      logger: .disabled,
      transport: MockTransport([])
    )
    do {
      _ = try await client.models.list()
      XCTFail("Expected authentication provider failure")
    } catch let error as HeaderProviderError {
      XCTAssertEqual(error, .signedOut)
    }
  }

  func testAdditionalSensitiveHeadersAreRedacted() {
    let redacted = redactHeaders(
      ["X-App-JWT": "secret-session-token", "X-Trace": "safe"],
      additionalSensitiveHeaders: ["x-app-jwt"]
    )
    XCTAssertEqual(redacted["X-App-JWT"], "***oken")
    XCTAssertEqual(redacted["X-Trace"], "safe")
  }

  func testDebugLoggingRedactsBodiesByDefault() async throws {
    let logs = LockedLogCollector()
    let transport = MockTransport([.response(jsonResponse(modelsJSON))])
    let client = try TypeSafeClient(
      authentication: .headers(["X-App-Token": "secret-session-token"]),
      baseURL: "https://proxy.example",
      logLevel: .debug,
      logger: TypeSafeLogger { _, message in logs.append(message) },
      transport: transport
    )

    _ = try await client.models.list()

    let rendered = logs.snapshot().joined(separator: "\n")
    XCTAssertTrue(rendered.contains("<redacted;"))
    XCTAssertFalse(rendered.contains("Latest model"))
    XCTAssertFalse(rendered.contains("secret-session-token"))
    XCTAssertFalse(client.logsBodies)
  }
}
