import XCTest

@testable import TypeSafe

final class ConfigurationTests: XCTestCase {
  func testDefaults() throws {
    let client = try TypeSafeClient(apiKey: "k", logger: .disabled)
    XCTAssertEqual(client.baseURL.absoluteString, TypeSafeClient.defaultBaseURL)
    XCTAssertEqual(client.defaultModel, "jev-latest")
    XCTAssertEqual(client.logLevel, .warn)
    XCTAssertEqual(client.timeoutMilliseconds, 10_000)
    XCTAssertEqual(client.retry, .default)
    XCTAssertFalse(client.logsBodies)
    XCTAssertTrue(client.usesTypeSafeAPIKey)
  }

  func testEnvironmentAndExplicitPrecedence() throws {
    let transport = MockTransport([])
    let client = try TypeSafeClient(
      apiKey: "code-key",
      baseURL: "https://code.test///",
      defaultModel: "code-model",
      logLevel: .error,
      logger: .disabled,
      retry: nil,
      timeoutMilliseconds: 123,
      defaultHeaders: [:],
      transport: transport,
      environment: [
        TypeSafeEnvironment.apiKey: "env-key",
        TypeSafeEnvironment.baseURL: "https://env.test",
        TypeSafeEnvironment.defaultModel: "env-model",
        TypeSafeEnvironment.logLevel: "debug",
      ]
    )
    XCTAssertEqual(client.baseURL.absoluteString, "https://code.test")
    XCTAssertEqual(client.defaultModel, "code-model")
    XCTAssertEqual(client.logLevel, .error)
    XCTAssertEqual(client.timeoutMilliseconds, 123)
  }

  func testBlankEnvironmentFallsBackAndMissingKeyFails() throws {
    XCTAssertThrowsError(
      try TypeSafeClient(
        apiKey: nil,
        baseURL: nil,
        defaultModel: nil,
        logLevel: nil,
        logger: .disabled,
        retry: nil,
        timeoutMilliseconds: 10_000,
        defaultHeaders: [:],
        transport: MockTransport([]),
        environment: [TypeSafeEnvironment.apiKey: "  "]
      )
    ) { error in
      XCTAssertTrue(error is TypeSafeConfigurationError)
      XCTAssertTrue(String(describing: error).contains(TypeSafeEnvironment.apiKey))
    }
  }

  func testInvalidConfigurationFailsEarly() throws {
    XCTAssertThrowsError(try TypeSafeClient(apiKey: "k", baseURL: "not a URL", logger: .disabled))
    XCTAssertThrowsError(
      try TypeSafeClient(apiKey: "k", baseURL: "https://user:pass@example.test", logger: .disabled)
    )
    XCTAssertThrowsError(
      try TypeSafeClient(
        apiKey: "k", baseURL: "https://example.test?token=secret", logger: .disabled)
    )
    XCTAssertThrowsError(try TypeSafeClient(apiKey: "k", logger: .disabled, timeoutMilliseconds: 0))
    XCTAssertThrowsError(try RetryPolicy(maxRetries: -1))
    XCTAssertThrowsError(try RetryPolicy(backoffJitter: 1.1))
    XCTAssertThrowsError(try RetryPolicy(httpStatuses: [42]))
  }

  func testAPIKeyAndAuthenticationAreMutuallyExclusive() throws {
    XCTAssertThrowsError(
      try TypeSafeClient(
        apiKey: "typesafe-key",
        authentication: .bearerToken("app-token"),
        logger: .disabled
      )
    ) { error in
      XCTAssertTrue(String(describing: error).contains("either apiKey or authentication"))
    }
  }

  func testDirectAPIKeyIsBlockedOnClientPlatformsUnlessExplicitlyAllowed() throws {
    XCTAssertThrowsError(
      try TypeSafeClient(
        apiKey: "typesafe-key",
        baseURL: nil,
        defaultModel: nil,
        logLevel: nil,
        logger: .disabled,
        retry: nil,
        timeoutMilliseconds: 10_000,
        defaultHeaders: [:],
        transport: MockTransport([]),
        environment: [:],
        isClientPlatform: true
      )
    ) { error in
      XCTAssertTrue(String(describing: error).contains("iOS, iPadOS"))
    }

    let client = try TypeSafeClient(
      apiKey: "typesafe-key",
      baseURL: nil,
      defaultModel: nil,
      logLevel: nil,
      logger: .disabled,
      retry: nil,
      timeoutMilliseconds: 10_000,
      defaultHeaders: [:],
      dangerouslyAllowAPIKeyInClient: true,
      transport: MockTransport([]),
      environment: [:],
      isClientPlatform: true
    )
    XCTAssertTrue(client.usesTypeSafeAPIKey)
  }

  func testRemoteHTTPRequiresExplicitDevelopmentOptIn() throws {
    XCTAssertThrowsError(
      try TypeSafeClient(
        authentication: .unauthenticated,
        baseURL: "http://proxy.example",
        logger: .disabled
      ))

    XCTAssertNoThrow(
      try TypeSafeClient(
        authentication: .unauthenticated,
        baseURL: "http://127.0.0.1:8080/typesafe",
        logger: .disabled
      ))

    let insecure = try TypeSafeClient(
      authentication: .unauthenticated,
      baseURL: "http://dev-proxy.example",
      logger: .disabled,
      allowsInsecureHTTP: true
    )
    XCTAssertTrue(insecure.allowsInsecureHTTP)
  }

  func testInvalidEnvironmentLogLevelNamesSource() throws {
    XCTAssertThrowsError(
      try TypeSafeClient(
        apiKey: "k",
        baseURL: nil,
        defaultModel: nil,
        logLevel: nil,
        logger: .disabled,
        retry: nil,
        timeoutMilliseconds: 10_000,
        defaultHeaders: [:],
        transport: MockTransport([]),
        environment: [TypeSafeEnvironment.logLevel: "loud"]
      )
    ) { error in
      let message = String(describing: error)
      XCTAssertTrue(message.contains("loud"))
      XCTAssertTrue(message.contains(TypeSafeEnvironment.logLevel))
    }
  }

  func testPublicValuesAreSendable() throws {
    func requireSendable<T: Sendable>(_: T) {}
    requireSendable(try TypeSafeClient(apiKey: "k", logger: .disabled))
    requireSendable(JSONValue.object(["ok": true]))
    requireSendable(noul("question"))
    requireSendable(RetryPolicy.default)
  }
}
