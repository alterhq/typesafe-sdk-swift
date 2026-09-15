import Foundation

/// Marker protocol shared by errors produced by the TypeSafe SDK.
public protocol TypeSafeError: Error, Sendable, CustomStringConvertible {}

/// Invalid SDK configuration or request input.
public struct TypeSafeConfigurationError: TypeSafeError, Equatable {
  public let message: String

  public init(_ message: String) { self.message = message }
  public var description: String { message }
}

/// The parsed body of an unsuccessful API response.
public enum APIErrorBody: Sendable, Hashable {
  case json(JSONValue)
  case text(String)
  case empty
}

/// An unsuccessful HTTP response from the TypeSafe API.
public struct APIError: TypeSafeError {
  public enum Kind: String, Sendable, Hashable {
    case badRequest
    case authentication
    case permissionDenied
    case notFound
    case unprocessableEntity
    case rateLimit
    case internalServer
    case other
  }

  public let kind: Kind
  public let status: Int
  public let body: APIErrorBody
  public let headers: [String: String]
  public let requestID: String?
  public let retryAfterMilliseconds: Int?
  public let message: String

  public init(
    status: Int,
    body: APIErrorBody,
    headers: [String: String],
    endpoint: String? = nil,
    now: Date = Date()
  ) {
    self.status = status
    self.body = body
    self.headers = headers
    kind = Self.kind(for: status)
    requestID = Self.header("x-typesafe-request-id", in: headers)
    retryAfterMilliseconds =
      kind == .rateLimit
      ? RetryPolicy.retryAfterMilliseconds(headers: headers, now: now)
      : nil

    var rendered = "\(status) \(Self.message(from: body))"
    if let endpoint { rendered = "\(endpoint): \(rendered)" }
    if let requestID { rendered += " (request_id=\(requestID))" }
    message = rendered
  }

  public var description: String { message }

  public static func kind(for status: Int) -> Kind {
    switch status {
    case 400: .badRequest
    case 401: .authentication
    case 403: .permissionDenied
    case 404: .notFound
    case 422: .unprocessableEntity
    case 429: .rateLimit
    case 500...: .internalServer
    default: .other
    }
  }

  static func header(_ name: String, in headers: [String: String]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  private static func message(from body: APIErrorBody) -> String {
    switch body {
    case .empty:
      return "status code (no body)"
    case let .text(text):
      return truncate(text)
    case let .json(json):
      if let extracted = extractMessage(json) { return extracted }
      return truncate(json.description)
    }
  }

  private static func truncate(_ value: String) -> String {
    guard value.count > 200 else { return value }
    return String(value.prefix(200)) + "…"
  }

  private static func extractMessage(_ value: JSONValue) -> String? {
    guard case let .object(object) = value else { return nil }
    if case let .string(message)? = object["error"] { return message }
    if case let .object(error)? = object["error"],
      case let .string(message)? = error["message"]
    {
      return message
    }
    if case let .string(message)? = object["message"] { return message }
    if case let .string(message)? = object["detail"] { return message }
    if case let .object(detail)? = object["detail"],
      case let .string(message)? = detail["message"]
    {
      return message
    }
    if case let .array(errors)? = object["detail"] {
      let parts = errors.compactMap(validationErrorDescription)
      return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
    return nil
  }

  private static func validationErrorDescription(_ value: JSONValue) -> String? {
    guard case let .object(error) = value,
      case let .string(message)? = error["msg"]
    else { return nil }

    guard case let .array(location)? = error["loc"] else { return message }
    let path = location.compactMap { component -> String? in
      switch component {
      case let .string(value) where value != "body": value
      case let .integer(value): String(value)
      default: nil
      }
    }.joined(separator: ".")
    return path.isEmpty ? message : "\(path): \(message)"
  }
}

/// A request failed without receiving an HTTP response.
public struct APIConnectionError: TypeSafeError {
  public let message: String
  public init(_ message: String = "Connection error.") { self.message = message }
  public var description: String { message }
}

/// An attempt exceeded its configured timeout.
public struct APITimeoutError: TypeSafeError, Equatable {
  public let timeoutMilliseconds: Int
  public init(timeoutMilliseconds: Int) { self.timeoutMilliseconds = timeoutMilliseconds }
  public var description: String { "Request timed out after \(timeoutMilliseconds)ms." }
}

/// The calling Swift task cancelled the request or a pending retry.
public struct APIUserAbortError: TypeSafeError, Equatable {
  public init() {}
  public var description: String { "Request was cancelled." }
}

/// A successful response did not match the documented API schema.
public struct APIResponseValidationError: TypeSafeError {
  public let status: Int
  public let body: APIErrorBody
  public let headers: [String: String]
  public let requestID: String?
  public let fieldPath: String
  public let endpoint: String

  public init(
    status: Int,
    body: APIErrorBody,
    headers: [String: String],
    fieldPath: String,
    endpoint: String
  ) {
    self.status = status
    self.body = body
    self.headers = headers
    requestID = APIError.header("x-typesafe-request-id", in: headers)
    self.fieldPath = fieldPath
    self.endpoint = endpoint
  }

  public var description: String {
    var value = "\(endpoint): \(status) Invalid response data at \"\(fieldPath)\"."
    if let requestID { value += " (request_id=\(requestID))" }
    return value
  }
}
