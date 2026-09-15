import Foundation

/// Information available when producing headers for an outgoing request.
public struct AuthenticationContext: Sendable, Hashable {
  public let method: HTTPMethod
  public let url: URL
  /// Zero for the initial request and incremented for each SDK retry.
  public let attempt: Int

  public init(method: HTTPMethod, url: URL, attempt: Int) {
    self.method = method
    self.url = url
    self.attempt = attempt
  }
}

/// Supplies authentication or other dynamic headers without coupling the SDK to an auth system.
///
/// The provider is evaluated before every attempt, allowing an application to refresh an expired
/// session token before an SDK retry. Provider errors are returned to the caller unchanged.
public struct TypeSafeAuthentication: Sendable {
  public typealias HeaderProvider =
    @Sendable (AuthenticationContext) async throws -> [String: String]

  let sensitiveHeaderNames: Set<String>
  let usesTypeSafeAPIKey: Bool
  private let provider: HeaderProvider

  public init(
    sensitiveHeaderNames: Set<String> = [],
    provider: @escaping HeaderProvider
  ) {
    self.sensitiveHeaderNames = Set(sensitiveHeaderNames.map { $0.lowercased() })
    usesTypeSafeAPIKey = false
    self.provider = provider
  }

  /// Sends no authentication headers. Use this when a proxy authenticates by another mechanism,
  /// such as an HTTP-only cookie managed by the networking stack.
  public static let unauthenticated = TypeSafeAuthentication { _ in [:] }

  /// Sends a fixed Bearer token, such as an application session token accepted by a proxy.
  public static func bearerToken(_ token: String) -> TypeSafeAuthentication {
    TypeSafeAuthentication(sensitiveHeaderNames: ["Authorization"]) { _ in
      ["Authorization": "Bearer \(token)"]
    }
  }

  /// Resolves a Bearer token before every request attempt.
  public static func bearerToken(
    provider: @escaping @Sendable (AuthenticationContext) async throws -> String
  ) -> TypeSafeAuthentication {
    TypeSafeAuthentication(sensitiveHeaderNames: ["Authorization"]) { context in
      ["Authorization": "Bearer \(try await provider(context))"]
    }
  }

  /// Sends fixed headers to a proxy. Provider-produced headers are redacted from debug logs.
  public static func headers(
    _ headers: [String: String],
    sensitiveHeaderNames: Set<String> = []
  ) -> TypeSafeAuthentication {
    TypeSafeAuthentication(sensitiveHeaderNames: sensitiveHeaderNames) { _ in headers }
  }

  /// Resolves arbitrary proxy headers before every request attempt.
  public static func headers(
    sensitiveHeaderNames: Set<String> = [],
    provider: @escaping HeaderProvider
  ) -> TypeSafeAuthentication {
    TypeSafeAuthentication(sensitiveHeaderNames: sensitiveHeaderNames, provider: provider)
  }

  func headers(for context: AuthenticationContext) async throws -> [String: String] {
    try await provider(context)
  }

  static func typeSafeAPIKey(_ key: String) -> TypeSafeAuthentication {
    TypeSafeAuthentication(
      sensitiveHeaderNames: ["Authorization"],
      usesTypeSafeAPIKey: true
    ) { _ in
      ["Authorization": "Bearer \(key)"]
    }
  }

  private init(
    sensitiveHeaderNames: Set<String>,
    usesTypeSafeAPIKey: Bool,
    provider: @escaping HeaderProvider
  ) {
    self.sensitiveHeaderNames = Set(sensitiveHeaderNames.map { $0.lowercased() })
    self.usesTypeSafeAPIKey = usesTypeSafeAPIKey
    self.provider = provider
  }
}
