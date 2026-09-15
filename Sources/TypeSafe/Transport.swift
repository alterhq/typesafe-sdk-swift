import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum HTTPMethod: String, Sendable, Hashable {
  case get = "GET"
  case post = "POST"
}

/// A fully prepared request handed to the SDK's HTTP transport.
public struct HTTPRequest: Sendable, Hashable {
  public let method: HTTPMethod
  public let url: URL
  public let headers: [String: String]
  public let body: Data?
  public let timeoutMilliseconds: Int

  public init(
    method: HTTPMethod,
    url: URL,
    headers: [String: String],
    body: Data?,
    timeoutMilliseconds: Int
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}

/// A buffered HTTP response returned by a transport.
public struct HTTPResponse: Sendable, Hashable {
  public let statusCode: Int
  public let headers: [String: String]
  public let body: Data

  public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
    self.statusCode = statusCode
    self.headers = headers
    self.body = body
  }

  public var requestID: String? {
    APIError.header("x-typesafe-request-id", in: headers)
  }

  public func header(_ name: String) -> String? {
    APIError.header(name, in: headers)
  }
}

/// A parsed SDK value together with the complete HTTP response and request ID.
public struct TypeSafeResponse<Value: Sendable>: Sendable {
  public let data: Value
  public let response: HTTPResponse
  public let requestID: String?

  public init(data: Value, response: HTTPResponse) {
    self.data = data
    self.response = response
    requestID = response.requestID
  }
}

/// Injectable HTTP boundary used by the live client and deterministic tests.
public protocol HTTPTransport: Sendable {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The default Foundation `URLSession` transport.
public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.httpBody = request.body
    urlRequest.timeoutInterval = Double(request.timeoutMilliseconds) / 1_000
    for (name, value) in request.headers {
      urlRequest.setValue(value, forHTTPHeaderField: name)
    }

    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else {
      throw APIConnectionError("The server returned a non-HTTP response.")
    }
    let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, entry in
      result[String(describing: entry.key)] = String(describing: entry.value)
    }
    return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
  }
}

struct HeaderMap {
  private var values: [String: (name: String, value: String)] = [:]

  init(_ headers: [String: String] = [:]) {
    merge(headers)
  }

  mutating func merge(_ headers: [String: String]) {
    for (name, value) in headers {
      values[name.lowercased()] = (name, value)
    }
  }

  mutating func set(_ name: String, _ value: String?) {
    if let value {
      values[name.lowercased()] = (name, value)
    } else {
      values.removeValue(forKey: name.lowercased())
    }
  }

  var dictionary: [String: String] {
    Dictionary(uniqueKeysWithValues: values.values.map { ($0.name, $0.value) })
  }
}
