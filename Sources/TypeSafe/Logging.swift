import Foundation

public enum LogLevel: String, Sendable, Hashable, Codable, CaseIterable {
  case debug, info, warn, error, off

  var rank: Int {
    switch self {
    case .debug: 0
    case .info: 1
    case .warn: 2
    case .error: 3
    case .off: 4
    }
  }
}

/// A concurrency-safe logging sink.
public struct TypeSafeLogger: Sendable {
  private let handler: @Sendable (LogLevel, String) -> Void

  public init(_ handler: @escaping @Sendable (LogLevel, String) -> Void) {
    self.handler = handler
  }

  public func log(_ level: LogLevel, _ message: String) {
    handler(level, message)
  }

  public static let console = TypeSafeLogger { level, message in
    print("[typesafe-sdk] [\(level.rawValue)] \(message)")
  }

  public static let disabled = TypeSafeLogger { _, _ in }
}

func redactHeaders(
  _ headers: [String: String],
  additionalSensitiveHeaders: Set<String> = []
) -> [String: String] {
  let keyed =
    Set(["authorization", "proxy-authorization", "x-api-key"])
    .union(additionalSensitiveHeaders.map { $0.lowercased() })
  let opaque = Set(["cookie", "set-cookie"])
  return headers.mapValues { $0 }.reduce(into: [:]) { result, entry in
    let lower = entry.key.lowercased()
    if opaque.contains(lower) {
      result[entry.key] = "***"
    } else if keyed.contains(lower) {
      let pieces = entry.value.split(maxSplits: 1, whereSeparator: \.isWhitespace)
      let scheme = pieces.count == 2 ? String(pieces[0]) + " " : ""
      let secret = pieces.count == 2 ? String(pieces[1]) : entry.value
      let suffix = secret.count > 8 ? String(secret.suffix(4)) : ""
      result[entry.key] = scheme + "***" + suffix
    } else {
      result[entry.key] = entry.value
    }
  }
}
