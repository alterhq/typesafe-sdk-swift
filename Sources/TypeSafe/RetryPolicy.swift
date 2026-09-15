import Foundation

/// Retry behavior for API calls.
public struct RetryPolicy: Sendable, Hashable {
  public let maxRetries: Int
  public let backoffInitialMilliseconds: Int
  public let backoffMaxMilliseconds: Int
  public let backoffJitter: Double
  public let httpStatuses: Set<Int>
  public let respectRetryAfter: Bool
  public let maxRetryAfterMilliseconds: Int
  public let retryConnectionErrors: Bool
  public let retryTimeoutErrors: Bool

  public init(
    maxRetries: Int = 2,
    backoffInitialMilliseconds: Int = 500,
    backoffMaxMilliseconds: Int = 5_000,
    backoffJitter: Double = 0.25,
    httpStatuses: Set<Int> = Set([408, 429]).union(500...599),
    respectRetryAfter: Bool = true,
    maxRetryAfterMilliseconds: Int = 60_000,
    retryConnectionErrors: Bool = true,
    retryTimeoutErrors: Bool = true
  ) throws {
    guard maxRetries >= 0 else {
      throw TypeSafeConfigurationError("retry.maxRetries must be a non-negative integer.")
    }
    guard backoffInitialMilliseconds >= 0 else {
      throw TypeSafeConfigurationError("retry.backoffInitialMilliseconds must be non-negative.")
    }
    guard backoffMaxMilliseconds >= 0 else {
      throw TypeSafeConfigurationError("retry.backoffMaxMilliseconds must be non-negative.")
    }
    guard backoffJitter.isFinite, (0...1).contains(backoffJitter) else {
      throw TypeSafeConfigurationError("retry.backoffJitter must be between zero and one.")
    }
    guard maxRetryAfterMilliseconds >= 0 else {
      throw TypeSafeConfigurationError("retry.maxRetryAfterMilliseconds must be non-negative.")
    }
    guard httpStatuses.allSatisfy({ (100...999).contains($0) }) else {
      throw TypeSafeConfigurationError("retry.httpStatuses must contain valid HTTP status codes.")
    }
    self.maxRetries = maxRetries
    self.backoffInitialMilliseconds = backoffInitialMilliseconds
    self.backoffMaxMilliseconds = backoffMaxMilliseconds
    self.backoffJitter = backoffJitter
    self.httpStatuses = httpStatuses
    self.respectRetryAfter = respectRetryAfter
    self.maxRetryAfterMilliseconds = maxRetryAfterMilliseconds
    self.retryConnectionErrors = retryConnectionErrors
    self.retryTimeoutErrors = retryTimeoutErrors
  }

  public static let `default` = RetryPolicy(
    maxRetries: 2,
    backoffInitialMilliseconds: 500,
    backoffMaxMilliseconds: 5_000,
    backoffJitter: 0.25,
    httpStatuses: Set([408, 429]).union(500...599),
    respectRetryAfter: true,
    maxRetryAfterMilliseconds: 60_000,
    retryConnectionErrors: true,
    retryTimeoutErrors: true,
    validated: ()
  )

  private init(
    maxRetries: Int,
    backoffInitialMilliseconds: Int,
    backoffMaxMilliseconds: Int,
    backoffJitter: Double,
    httpStatuses: Set<Int>,
    respectRetryAfter: Bool,
    maxRetryAfterMilliseconds: Int,
    retryConnectionErrors: Bool,
    retryTimeoutErrors: Bool,
    validated: Void
  ) {
    self.maxRetries = maxRetries
    self.backoffInitialMilliseconds = backoffInitialMilliseconds
    self.backoffMaxMilliseconds = backoffMaxMilliseconds
    self.backoffJitter = backoffJitter
    self.httpStatuses = httpStatuses
    self.respectRetryAfter = respectRetryAfter
    self.maxRetryAfterMilliseconds = maxRetryAfterMilliseconds
    self.retryConnectionErrors = retryConnectionErrors
    self.retryTimeoutErrors = retryTimeoutErrors
  }

  func applying(_ overrides: RetryPolicyOverrides?) throws -> RetryPolicy {
    guard let overrides else { return self }
    return try RetryPolicy(
      maxRetries: overrides.maxRetries ?? maxRetries,
      backoffInitialMilliseconds: overrides.backoffInitialMilliseconds
        ?? backoffInitialMilliseconds,
      backoffMaxMilliseconds: overrides.backoffMaxMilliseconds ?? backoffMaxMilliseconds,
      backoffJitter: overrides.backoffJitter ?? backoffJitter,
      httpStatuses: overrides.httpStatuses ?? httpStatuses,
      respectRetryAfter: overrides.respectRetryAfter ?? respectRetryAfter,
      maxRetryAfterMilliseconds: overrides.maxRetryAfterMilliseconds ?? maxRetryAfterMilliseconds,
      retryConnectionErrors: overrides.retryConnectionErrors ?? retryConnectionErrors,
      retryTimeoutErrors: overrides.retryTimeoutErrors ?? retryTimeoutErrors
    )
  }

  func delayMilliseconds(
    attempt: Int,
    headers: [String: String]?,
    now: Date = Date(),
    random: Double = Double.random(in: 0..<1)
  ) -> Int {
    if respectRetryAfter,
      let headers,
      let requested = Self.retryAfterMilliseconds(headers: headers, now: now),
      requested <= maxRetryAfterMilliseconds
    {
      return requested
    }

    let exponent = pow(2.0, Double(attempt))
    let exponential = min(
      Double(backoffInitialMilliseconds) * exponent, Double(backoffMaxMilliseconds))
    return Int((exponential * (1 - random * backoffJitter)).rounded())
  }

  static func retryAfterMilliseconds(headers: [String: String], now: Date = Date()) -> Int? {
    if let raw = APIError.header("retry-after-ms", in: headers)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    {
      if raw.isEmpty { return 0 }
      if let milliseconds = Double(raw), milliseconds.isFinite, milliseconds >= 0 {
        return Int(milliseconds.rounded())
      }
    }
    guard
      let raw = APIError.header("retry-after", in: headers)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
    else {
      return nil
    }
    if raw.isEmpty { return 0 }
    if let seconds = Double(raw), seconds.isFinite {
      guard seconds >= 0 else { return nil }
      return Int((seconds * 1_000).rounded())
    }
    for format in [
      "EEE',' dd MMM yyyy HH':'mm':'ss z",
      "EEEE',' dd-MMM-yy HH':'mm':'ss z",
      "EEE MMM d HH':'mm':'ss yyyy",
    ] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = format
      if let date = formatter.date(from: raw) {
        return max(0, Int((date.timeIntervalSince(now) * 1_000).rounded()))
      }
    }
    return nil
  }
}

/// Field-by-field per-call overrides of a client's retry policy.
public struct RetryPolicyOverrides: Sendable, Hashable {
  public var maxRetries: Int?
  public var backoffInitialMilliseconds: Int?
  public var backoffMaxMilliseconds: Int?
  public var backoffJitter: Double?
  public var httpStatuses: Set<Int>?
  public var respectRetryAfter: Bool?
  public var maxRetryAfterMilliseconds: Int?
  public var retryConnectionErrors: Bool?
  public var retryTimeoutErrors: Bool?

  public init(
    maxRetries: Int? = nil,
    backoffInitialMilliseconds: Int? = nil,
    backoffMaxMilliseconds: Int? = nil,
    backoffJitter: Double? = nil,
    httpStatuses: Set<Int>? = nil,
    respectRetryAfter: Bool? = nil,
    maxRetryAfterMilliseconds: Int? = nil,
    retryConnectionErrors: Bool? = nil,
    retryTimeoutErrors: Bool? = nil
  ) {
    self.maxRetries = maxRetries
    self.backoffInitialMilliseconds = backoffInitialMilliseconds
    self.backoffMaxMilliseconds = backoffMaxMilliseconds
    self.backoffJitter = backoffJitter
    self.httpStatuses = httpStatuses
    self.respectRetryAfter = respectRetryAfter
    self.maxRetryAfterMilliseconds = maxRetryAfterMilliseconds
    self.retryConnectionErrors = retryConnectionErrors
    self.retryTimeoutErrors = retryTimeoutErrors
  }
}

/// Per-call transport options.
public struct RequestOptions: Sendable, Hashable {
  public var timeoutMilliseconds: Int?
  public var retry: RetryPolicyOverrides?
  public var headers: [String: String]

  public init(
    timeoutMilliseconds: Int? = nil,
    retry: RetryPolicyOverrides? = nil,
    headers: [String: String] = [:]
  ) {
    self.timeoutMilliseconds = timeoutMilliseconds
    self.retry = retry
    self.headers = headers
  }
}
