#if canImport(Darwin)
  import Foundation
  import XCTest
  @testable import TypeSafe

  private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response = HTTPResponse(statusCode: 200)
    nonisolated(unsafe) static var capturedRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      Self.capturedRequest = request
      let stub = Self.response
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: stub.statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: stub.headers
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: stub.body)
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  final class URLSessionTransportTests: XCTestCase {
    override func tearDown() {
      StubURLProtocol.capturedRequest = nil
      StubURLProtocol.response = HTTPResponse(statusCode: 200)
      super.tearDown()
    }

    func testURLSessionTransportConvertsRequestAndBuffersResponse() async throws {
      StubURLProtocol.response = HTTPResponse(
        statusCode: 201,
        headers: ["X-Result": "ok"],
        body: Data("created".utf8)
      )
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [StubURLProtocol.self]
      let session = URLSession(configuration: configuration)
      let transport = URLSessionTransport(session: session)
      let request = HTTPRequest(
        method: .post,
        url: URL(string: "https://example.test/v1/systemone")!,
        headers: ["X-Test": "yes"],
        body: Data("body".utf8),
        timeoutMilliseconds: 321
      )

      let response = try await transport.send(request)
      XCTAssertEqual(response.statusCode, 201)
      XCTAssertEqual(response.header("x-result"), "ok")
      XCTAssertEqual(String(data: response.body, encoding: .utf8), "created")
      XCTAssertEqual(StubURLProtocol.capturedRequest?.httpMethod, "POST")
      XCTAssertEqual(StubURLProtocol.capturedRequest?.value(forHTTPHeaderField: "X-Test"), "yes")
      let timeout = try XCTUnwrap(StubURLProtocol.capturedRequest?.timeoutInterval)
      XCTAssertEqual(timeout, 0.321, accuracy: 0.001)
      session.invalidateAndCancel()
    }
  }
#endif
