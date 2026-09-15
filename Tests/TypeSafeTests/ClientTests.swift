import XCTest

@testable import TypeSafe

final class ClientTests: XCTestCase {
  func testModelsListRequestAndResponse() async throws {
    let transport = MockTransport([
      .response(jsonResponse(modelsJSON, headers: ["X-TypeSafe-Request-ID": "req_models"]))
    ])
    let client = try TypeSafeClient(
      apiKey: "secret",
      baseURL: "https://example.test/",
      logger: .disabled,
      defaultHeaders: ["X-Trace": "default", "Authorization": "wrong"],
      transport: transport
    )

    let result = try await client.models.listWithResponse(
      options: .init(headers: ["x-trace": "call"]))
    XCTAssertEqual(
      result.data,
      [.init(name: "jev-latest", description: "Latest model", releaseDate: "2026-09-15")])
    XCTAssertEqual(result.requestID, "req_models")

    let captured = await transport.requests()
    let request = try XCTUnwrap(captured.first)
    XCTAssertEqual(request.method, .get)
    XCTAssertEqual(request.url.absoluteString, "https://example.test/v1/models")
    XCTAssertEqual(header("authorization", in: request), "Bearer secret")
    XCTAssertEqual(header("accept", in: request), "application/json")
    XCTAssertEqual(header("x-trace", in: request), "call")
    XCTAssertEqual(header("user-agent", in: request), "typesafe-sdk/0.6.0")
    XCTAssertEqual(header("x-typesafe-sdk", in: request), "typesafe-sdk/0.6.0")
    XCTAssertTrue(try XCTUnwrap(header("x-typesafe-runtime", in: request)).hasPrefix("swift/6"))
    XCTAssertNil(header("content-type", in: request))
  }

  func testSystemOnePayloadDefaultModelAndAdditionalFields() async throws {
    let transport = MockTransport([.response(jsonResponse(systemOneJSON))])
    let client = try TypeSafeClient(apiKey: "k", logger: .disabled, transport: transport)
    let response = try await client.systemOne(
      SystemOneRequest(
        state: ["document": "charged twice"],
        questions: ["category": choice("What is this?", criteria: ["billing": nil, "other": nil])],
        additionalFields: ["future_option": nil, "nested": ["enabled": true]]
      ))
    XCTAssertEqual(response.choices["category"]?.choice, "billing")

    let captured = await transport.requests()
    let request = try XCTUnwrap(captured.first)
    XCTAssertEqual(request.method, .post)
    XCTAssertEqual(header("content-type", in: request), "application/json")
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["model"] as? String, "jev-latest")
    XCTAssertTrue(object["future_option"] is NSNull)
    XCTAssertEqual((object["nested"] as? [String: Any])?["enabled"] as? Bool, true)
    XCTAssertNotNil(object["state"])
    XCTAssertNotNil(object["questions"])
  }

  func testExplicitAndClientDefaultModels() async throws {
    let transport = MockTransport([
      .response(jsonResponse(systemOneJSON)),
      .response(jsonResponse(systemOneJSON)),
    ])
    let client = try TypeSafeClient(
      apiKey: "k", defaultModel: "client-model", logger: .disabled, transport: transport)
    let questions = ["q": noul("?")]
    _ = try await client.systemOne(SystemOneRequest(state: "s", questions: questions))
    _ = try await client.systemOne(
      SystemOneRequest(state: "s", questions: questions, model: "call-model"))
    let requests = await transport.requests()
    let first = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? [String: Any])
    let second = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].body)) as? [String: Any])
    XCTAssertEqual(first["model"] as? String, "client-model")
    XCTAssertEqual(second["model"] as? String, "call-model")
  }

  func testInvalidQuestionsFailBeforeTransport() async throws {
    let transport = MockTransport([])
    let client = try TypeSafeClient(apiKey: "k", logger: .disabled, transport: transport)
    do {
      _ = try await client.systemOne(SystemOneRequest(state: "s", questions: [:]))
      XCTFail("Expected failure")
    } catch {
      XCTAssertTrue(error is TypeSafeConfigurationError)
    }
    do {
      _ = try await client.systemOne(
        SystemOneRequest(state: "s", questions: ["q": score("?", criteria: ["only"])]))
      XCTFail("Expected failure")
    } catch {
      XCTAssertTrue(String(describing: error).contains("at least two"))
    }
    let captured = await transport.requests()
    XCTAssertTrue(captured.isEmpty)
  }

  func testMalformedSuccessIsResponseValidationError() async throws {
    let transport = MockTransport([
      .response(jsonResponse(#"{"models":null}"#, headers: ["x-typesafe-request-id": "req_bad"]))
    ])
    let client = try TypeSafeClient(apiKey: "k", logger: .disabled, transport: transport)
    do {
      _ = try await client.models.list()
      XCTFail("Expected response validation failure")
    } catch let error as APIResponseValidationError {
      XCTAssertEqual(error.status, 200)
      XCTAssertEqual(error.requestID, "req_bad")
      XCTAssertTrue(error.fieldPath.contains("models"))
    }
  }

  func testRawResponseDoesNotRequireValidJSON() async throws {
    let raw = HTTPResponse(
      statusCode: 200,
      headers: ["x-typesafe-request-id": "req_raw", "x-internal": "visible"],
      body: Data("not-json".utf8)
    )
    let transport = MockTransport([.response(raw)])
    let client = try TypeSafeClient(apiKey: "k", logger: .disabled, transport: transport)
    let response = try await client.models.listRawResponse()
    XCTAssertEqual(response, raw)
    XCTAssertEqual(response.requestID, "req_raw")
    XCTAssertEqual(response.header("X-Internal"), "visible")
  }
}
