import XCTest

@testable import TypeSafe

final class ErrorAndRetryTests: XCTestCase {
  func testStatusErrorsCarryKindBodyAndRequestMetadata() async throws {
    let cases: [(Int, APIError.Kind)] = [
      (400, .badRequest), (401, .authentication), (403, .permissionDenied),
      (404, .notFound), (422, .unprocessableEntity), (429, .rateLimit),
      (503, .internalServer), (409, .other),
    ]
    for (status, kind) in cases {
      let transport = MockTransport([
        .response(
          jsonResponse(
            #"{"message":"failed"}"#,
            status: status,
            headers: ["x-typesafe-request-id": "req_\(status)", "retry-after": "7"]
          ))
      ])
      let policy = try RetryPolicy(maxRetries: 0)
      let client = try TypeSafeClient(
        apiKey: "k", logger: .disabled, retry: policy, transport: transport)
      do {
        _ = try await client.models.list()
        XCTFail("Expected status \(status) to fail")
      } catch let error as APIError {
        XCTAssertEqual(error.status, status)
        XCTAssertEqual(error.kind, kind)
        XCTAssertEqual(error.requestID, "req_\(status)")
        XCTAssertTrue(error.description.contains("failed"))
        XCTAssertEqual(error.retryAfterMilliseconds, status == 429 ? 7_000 : nil)
      }
    }
  }

  func testValidationErrorMessageExtraction() {
    let body: APIErrorBody = .json([
      "detail": [["loc": ["body", "questions", "q"], "msg": "invalid"]]
    ])
    let error = APIError(status: 422, body: body, headers: [:])
    XCTAssertTrue(error.description.contains("questions.q: invalid"))
  }

  func testRetriesStatusThenSucceedsAndSendsRetryCount() async throws {
    let transport = MockTransport([
      .response(jsonResponse("{}", status: 503)),
      .response(jsonResponse(modelsJSON)),
    ])
    let policy = try RetryPolicy(
      backoffInitialMilliseconds: 0, backoffMaxMilliseconds: 0, backoffJitter: 0)
    let client = try TypeSafeClient(
      apiKey: "k", logger: .disabled, retry: policy, transport: transport)
    let models = try await client.models.list()
    XCTAssertEqual(models.count, 1)
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertNil(header("x-typesafe-retry-count", in: requests[0]))
    XCTAssertEqual(header("x-typesafe-retry-count", in: requests[1]), "1")
  }

  func testRetriesConnectionFailure() async throws {
    let transport = MockTransport([
      .failure(.disconnected),
      .response(jsonResponse(modelsJSON)),
    ])
    let policy = try RetryPolicy(
      backoffInitialMilliseconds: 0, backoffMaxMilliseconds: 0, backoffJitter: 0)
    let client = try TypeSafeClient(
      apiKey: "k", logger: .disabled, retry: policy, transport: transport)
    let models = try await client.models.list()
    let requests = await transport.requests()
    XCTAssertEqual(models.count, 1)
    XCTAssertEqual(requests.count, 2)
  }

  func testDoesNotRetryNonRetryableStatus() async throws {
    let transport = MockTransport([
      .response(jsonResponse("{}", status: 400)),
      .response(jsonResponse(modelsJSON)),
    ])
    let policy = try RetryPolicy(backoffInitialMilliseconds: 0, backoffMaxMilliseconds: 0)
    let client = try TypeSafeClient(
      apiKey: "k", logger: .disabled, retry: policy, transport: transport)
    do {
      _ = try await client.models.list()
      XCTFail("Expected failure")
    } catch let error as APIError {
      XCTAssertEqual(error.kind, .badRequest)
    }
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
  }

  func testPerCallOverrideDisablesRetries() async throws {
    let transport = MockTransport([
      .response(jsonResponse("{}", status: 503)),
      .response(jsonResponse(modelsJSON)),
    ])
    let policy = try RetryPolicy(
      maxRetries: 5, backoffInitialMilliseconds: 0, backoffMaxMilliseconds: 0)
    let client = try TypeSafeClient(
      apiKey: "k", logger: .disabled, retry: policy, transport: transport)
    do {
      _ = try await client.models.list(options: .init(retry: .init(maxRetries: 0)))
      XCTFail("Expected failure")
    } catch is APIError {}
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(client.retry.maxRetries, 5)
  }

  func testRetryAfterParsingAndCap() throws {
    XCTAssertEqual(RetryPolicy.retryAfterMilliseconds(headers: ["Retry-After": "2"]), 2_000)
    XCTAssertEqual(RetryPolicy.retryAfterMilliseconds(headers: ["retry-after-ms": "125"]), 125)
    XCTAssertNil(RetryPolicy.retryAfterMilliseconds(headers: ["retry-after": "-1"]))
    let policy = try RetryPolicy(
      backoffInitialMilliseconds: 10,
      backoffMaxMilliseconds: 10,
      backoffJitter: 0,
      maxRetryAfterMilliseconds: 1_000
    )
    XCTAssertEqual(
      policy.delayMilliseconds(attempt: 0, headers: ["retry-after": "2"], random: 0), 10)
  }

  func testTimeoutAndTaskCancellationHaveDistinctErrors() async throws {
    let timeoutTransport = MockTransport([.hang])
    let noRetries = try RetryPolicy(maxRetries: 0)
    let timeoutClient = try TypeSafeClient(
      apiKey: "k",
      logger: .disabled,
      retry: noRetries,
      timeoutMilliseconds: 10,
      transport: timeoutTransport
    )
    do {
      _ = try await timeoutClient.models.list()
      XCTFail("Expected timeout")
    } catch let error as APITimeoutError {
      XCTAssertEqual(error.timeoutMilliseconds, 10)
    }

    let cancelTransport = MockTransport([.hang])
    let cancelClient = try TypeSafeClient(
      apiKey: "k",
      logger: .disabled,
      retry: noRetries,
      timeoutMilliseconds: 60_000,
      transport: cancelTransport
    )
    let task = Task { try await cancelClient.models.list() }
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is APIUserAbortError {}
  }

  func testRedactionPreservesOnlySafeSuffix() {
    let redacted = redactHeaders([
      "Authorization": "Bearer super-secret-key",
      "Cookie": "session=secret",
      "X-Trace": "safe",
    ])
    XCTAssertEqual(redacted["Authorization"], "Bearer ***-key")
    XCTAssertEqual(redacted["Cookie"], "***")
    XCTAssertEqual(redacted["X-Trace"], "safe")
  }
}
