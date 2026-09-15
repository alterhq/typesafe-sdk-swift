import Foundation

public let typeSafeSDKVersion = "0.6.0"

public enum TypeSafeEnvironment {
  public static let apiKey = "TYPESAFE_API_KEY"
  public static let baseURL = "TYPESAFE_BASE_URL"
  public static let defaultModel = "TYPESAFE_DEFAULT_MODEL"
  public static let logLevel = "TYPESAFE_LOG_LEVEL"
}

/// A concurrency-safe client for the TypeSafe AI API.
public struct TypeSafeClient: Sendable {
  public static let defaultBaseURL = "https://api.typesafe.ai"
  public static let defaultModel = "jev-latest"
  public static let defaultTimeoutMilliseconds = 10_000

  public let baseURL: URL
  public let defaultModel: String
  public let logLevel: LogLevel
  public let retry: RetryPolicy
  public let timeoutMilliseconds: Int
  public let defaultHeaders: [String: String]
  public let logsBodies: Bool
  /// `true` only when the client authenticates directly with a TypeSafe API key.
  public let usesTypeSafeAPIKey: Bool
  public let allowsInsecureHTTP: Bool

  private let core: ClientCore

  public init(
    apiKey: String? = nil,
    authentication: TypeSafeAuthentication? = nil,
    baseURL: String? = nil,
    defaultModel: String? = nil,
    logLevel: LogLevel? = nil,
    logger: TypeSafeLogger = .console,
    logBodies: Bool = false,
    retry: RetryPolicy? = nil,
    timeoutMilliseconds: Int = TypeSafeClient.defaultTimeoutMilliseconds,
    defaultHeaders: [String: String] = [:],
    allowsInsecureHTTP: Bool = false,
    dangerouslyAllowAPIKeyInClient: Bool = false,
    transport: any HTTPTransport = URLSessionTransport()
  ) throws {
    try self.init(
      apiKey: apiKey,
      authentication: authentication,
      baseURL: baseURL,
      defaultModel: defaultModel,
      logLevel: logLevel,
      logger: logger,
      logBodies: logBodies,
      retry: retry,
      timeoutMilliseconds: timeoutMilliseconds,
      defaultHeaders: defaultHeaders,
      allowsInsecureHTTP: allowsInsecureHTTP,
      dangerouslyAllowAPIKeyInClient: dangerouslyAllowAPIKeyInClient,
      transport: transport,
      environment: ProcessInfo.processInfo.environment
    )
  }

  init(
    apiKey: String?,
    authentication: TypeSafeAuthentication? = nil,
    baseURL: String?,
    defaultModel: String?,
    logLevel: LogLevel?,
    logger: TypeSafeLogger,
    logBodies: Bool = false,
    retry: RetryPolicy?,
    timeoutMilliseconds: Int,
    defaultHeaders: [String: String],
    allowsInsecureHTTP: Bool = false,
    dangerouslyAllowAPIKeyInClient: Bool = false,
    transport: any HTTPTransport,
    environment: [String: String],
    isClientPlatform: Bool = TypeSafeClient.isClientPlatform
  ) throws {
    let environmentValue: (String) -> String? = { name in
      guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      else { return nil }
      return value
    }

    if apiKey != nil, authentication != nil {
      throw TypeSafeConfigurationError(
        "Pass either apiKey or authentication, not both. Use authentication for an app-authenticated proxy."
      )
    }

    let resolvedAuthentication: TypeSafeAuthentication
    if let authentication {
      // Supplying an authentication strategy deliberately bypasses TYPESAFE_API_KEY. This prevents
      // a developer's environment from leaking a direct API key into proxy requests.
      resolvedAuthentication = authentication
    } else {
      let explicitKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let resolvedKey = explicitKey ?? environmentValue(TypeSafeEnvironment.apiKey),
        !resolvedKey.isEmpty
      else {
        throw TypeSafeConfigurationError(
          "No API key was provided. Pass apiKey, set \(TypeSafeEnvironment.apiKey), or supply authentication for a proxy."
        )
      }
      guard !isClientPlatform || dangerouslyAllowAPIKeyInClient else {
        throw TypeSafeConfigurationError(
          "Embedding a TypeSafe API key in an iOS, iPadOS, tvOS, or watchOS app is unsafe. Route requests through your backend with authentication, or explicitly set dangerouslyAllowAPIKeyInClient for a controlled development build."
        )
      }
      resolvedAuthentication = .typeSafeAPIKey(resolvedKey)
    }

    let base = (baseURL ?? environmentValue(TypeSafeEnvironment.baseURL) ?? Self.defaultBaseURL)
      .replacingOccurrences(of: #"/+\z"#, with: "", options: .regularExpression)
    guard let resolvedBaseURL = URL(string: base),
      let scheme = resolvedBaseURL.scheme,
      ["http", "https"].contains(scheme.lowercased()),
      resolvedBaseURL.host != nil,
      resolvedBaseURL.user == nil,
      resolvedBaseURL.password == nil,
      resolvedBaseURL.query == nil,
      resolvedBaseURL.fragment == nil
    else {
      throw TypeSafeConfigurationError(
        "baseURL must be an absolute HTTP or HTTPS URL without credentials, a query, or a fragment."
      )
    }
    guard scheme.lowercased() == "https" || allowsInsecureHTTP || Self.isLoopback(resolvedBaseURL)
    else {
      throw TypeSafeConfigurationError(
        "baseURL must use HTTPS unless it is loopback. Set allowsInsecureHTTP only for a trusted development endpoint."
      )
    }
    guard timeoutMilliseconds > 0 else {
      throw TypeSafeConfigurationError("timeoutMilliseconds must be positive.")
    }

    let resolvedLogLevel: LogLevel
    if let logLevel {
      resolvedLogLevel = logLevel
    } else if let raw = environmentValue(TypeSafeEnvironment.logLevel) {
      guard let parsed = LogLevel(rawValue: raw) else {
        let expected = LogLevel.allCases.map(\.rawValue).joined(separator: ", ")
        throw TypeSafeConfigurationError(
          "Invalid log level \"\(raw)\" from \(TypeSafeEnvironment.logLevel). Expected one of: \(expected)."
        )
      }
      resolvedLogLevel = parsed
    } else {
      resolvedLogLevel = .warn
    }

    self.baseURL = resolvedBaseURL
    self.defaultModel =
      defaultModel ?? environmentValue(TypeSafeEnvironment.defaultModel) ?? Self.defaultModel
    self.logLevel = resolvedLogLevel
    self.retry = retry ?? .default
    self.timeoutMilliseconds = timeoutMilliseconds
    self.defaultHeaders = defaultHeaders
    logsBodies = logBodies
    usesTypeSafeAPIKey = resolvedAuthentication.usesTypeSafeAPIKey
    self.allowsInsecureHTTP = allowsInsecureHTTP
    core = ClientCore(
      authentication: resolvedAuthentication,
      baseURL: base,
      defaultModel: self.defaultModel,
      logLevel: resolvedLogLevel,
      logger: logger,
      logBodies: logBodies,
      retry: self.retry,
      timeoutMilliseconds: timeoutMilliseconds,
      defaultHeaders: defaultHeaders,
      transport: transport
    )
  }

  private static var isClientPlatform: Bool {
    #if os(iOS) || os(tvOS) || os(watchOS)
      true
    #else
      false
    #endif
  }

  private static func isLoopback(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }

  /// Access the models resource.
  public var models: Models { Models(core: core) }

  /// Answer named questions about text or structured state.
  public func systemOne(
    _ request: SystemOneRequest,
    options: RequestOptions = .init()
  ) async throws -> SystemOneResponse {
    try await systemOneWithResponse(request, options: options).data
  }

  /// Answer named questions and retain the complete HTTP response.
  public func systemOneWithResponse(
    _ request: SystemOneRequest,
    options: RequestOptions = .init()
  ) async throws -> TypeSafeResponse<SystemOneResponse> {
    try await core.systemOne(request, options: options)
  }

  /// Perform a System One request without decoding its successful response body.
  public func systemOneRawResponse(
    _ request: SystemOneRequest,
    options: RequestOptions = .init()
  ) async throws -> HTTPResponse {
    try await core.systemOneRawResponse(request, options: options)
  }
}

/// Access to the models available to the account.
public struct Models: Sendable {
  fileprivate let core: ClientCore

  public func list(options: RequestOptions = .init()) async throws -> [ModelCard] {
    try await listWithResponse(options: options).data
  }

  public func listWithResponse(
    options: RequestOptions = .init()
  ) async throws -> TypeSafeResponse<[ModelCard]> {
    try await core.listModels(options: options)
  }

  /// List models without decoding the successful response body.
  public func listRawResponse(options: RequestOptions = .init()) async throws -> HTTPResponse {
    try await core.listModelsRawResponse(options: options)
  }
}

private struct ModelsWire: Decodable, Sendable {
  let models: [ModelCard]
}

private enum AttemptResult: Sendable {
  case response(HTTPResponse)
  case timeout
}

actor ClientCore {
  private let authentication: TypeSafeAuthentication
  private let baseURL: String
  private let defaultModel: String
  private let logLevel: LogLevel
  private let logger: TypeSafeLogger
  private let logBodies: Bool
  private let retry: RetryPolicy
  private let timeoutMilliseconds: Int
  private let defaultHeaders: [String: String]
  private let transport: any HTTPTransport
  private var requestCount = 0

  init(
    authentication: TypeSafeAuthentication,
    baseURL: String,
    defaultModel: String,
    logLevel: LogLevel,
    logger: TypeSafeLogger,
    logBodies: Bool,
    retry: RetryPolicy,
    timeoutMilliseconds: Int,
    defaultHeaders: [String: String],
    transport: any HTTPTransport
  ) {
    self.authentication = authentication
    self.baseURL = baseURL
    self.defaultModel = defaultModel
    self.logLevel = logLevel
    self.logger = logger
    self.logBodies = logBodies
    self.retry = retry
    self.timeoutMilliseconds = timeoutMilliseconds
    self.defaultHeaders = defaultHeaders
    self.transport = transport
  }

  func systemOne(
    _ request: SystemOneRequest,
    options: RequestOptions
  ) async throws -> TypeSafeResponse<SystemOneResponse> {
    let response = try await systemOneRawResponse(request, options: options)
    return try decode(
      SystemOneResponse.self,
      from: response,
      endpoint: "POST \(baseURL)/v1/systemone"
    )
  }

  func systemOneRawResponse(
    _ request: SystemOneRequest,
    options: RequestOptions
  ) async throws -> HTTPResponse {
    guard !request.questions.isEmpty else {
      throw TypeSafeConfigurationError("At least one question is required.")
    }
    for (name, question) in request.questions {
      if case let .score(score) = question, score.criteria.count < 2 {
        throw TypeSafeConfigurationError(
          "Score question \"\(name)\" has \(score.criteria.count) criteria; at least two scores are required."
        )
      }
    }
    let payload: Data
    do {
      payload = try JSONEncoder.sorted.encode(
        SystemOnePayload(
          request: request,
          resolvedModel: request.model ?? defaultModel
        ))
    } catch {
      throw TypeSafeConfigurationError("The request body could not be encoded as JSON: \(error)")
    }
    return try await sendRaw(
      method: .post,
      path: "/v1/systemone",
      body: payload,
      options: options
    )
  }

  func listModels(options: RequestOptions) async throws -> TypeSafeResponse<[ModelCard]> {
    let response = try await listModelsRawResponse(options: options)
    let wire = try decode(
      ModelsWire.self,
      from: response,
      endpoint: "GET \(baseURL)/v1/models"
    )
    return TypeSafeResponse(data: wire.data.models, response: response)
  }

  func listModelsRawResponse(options: RequestOptions) async throws -> HTTPResponse {
    try await sendRaw(
      method: .get,
      path: "/v1/models",
      body: nil,
      options: options
    )
  }

  private func sendRaw(
    method: HTTPMethod,
    path: String,
    body: Data?,
    options: RequestOptions
  ) async throws -> HTTPResponse {
    guard let url = URL(string: baseURL + path) else {
      throw TypeSafeConfigurationError("Could not construct the request URL for \(path).")
    }
    let timeout = options.timeoutMilliseconds ?? timeoutMilliseconds
    guard timeout > 0 else {
      throw TypeSafeConfigurationError("timeoutMilliseconds must be positive.")
    }
    let policy = try retry.applying(options.retry)
    requestCount += 1
    let tag = "#\(requestCount) \(method.rawValue) \(path)"

    for attempt in 0...policy.maxRetries {
      do {
        try Task.checkCancellation()
      } catch is CancellationError {
        throw APIUserAbortError()
      }
      let authenticationHeaders: [String: String]
      do {
        authenticationHeaders = try await authentication.headers(
          for: AuthenticationContext(method: method, url: url, attempt: attempt))
      } catch is CancellationError {
        throw APIUserAbortError()
      }

      var attemptHeaders = HeaderMap(defaultHeaders)
      attemptHeaders.merge(options.headers)
      attemptHeaders.merge(authenticationHeaders)
      attemptHeaders.set("Accept", "application/json")
      attemptHeaders.set("User-Agent", "typesafe-sdk/\(typeSafeSDKVersion)")
      attemptHeaders.set("X-TypeSafe-SDK", "typesafe-sdk/\(typeSafeSDKVersion)")
      attemptHeaders.set("X-TypeSafe-Runtime", Self.runtimeDescription)
      attemptHeaders.set("Content-Type", body == nil ? nil : "application/json")
      attemptHeaders.set("X-TypeSafe-Retry-Count", nil)
      if attempt > 0 {
        attemptHeaders.set("X-TypeSafe-Retry-Count", String(attempt))
      }
      let request = HTTPRequest(
        method: method,
        url: url,
        headers: attemptHeaders.dictionary,
        body: body,
        timeoutMilliseconds: timeout
      )
      log(
        .debug,
        "\(tag) -> \(url.absoluteString) headers=\(redactHeaders(request.headers, additionalSensitiveHeaders: authentication.sensitiveHeaderNames.union(authenticationHeaders.keys.map { $0.lowercased() }))) body=\(loggedBody(body))"
      )

      let started = ContinuousClock.now
      let response: HTTPResponse
      do {
        response = try await performAttempt(request, timeoutMilliseconds: timeout)
      } catch is APIUserAbortError {
        throw APIUserAbortError()
      } catch let error as APITimeoutError {
        log(.info, "\(tag) timed out after \(elapsedMilliseconds(since: started))ms")
        guard attempt < policy.maxRetries, policy.retryTimeoutErrors else { throw error }
        try await backOff(
          tag: tag, attempt: attempt, reason: error.description, headers: nil, policy: policy)
        continue
      } catch let error as APIConnectionError {
        log(
          .info, "\(tag) connection error after \(elapsedMilliseconds(since: started))ms: \(error)")
        guard attempt < policy.maxRetries, policy.retryConnectionErrors else { throw error }
        try await backOff(
          tag: tag, attempt: attempt, reason: error.description, headers: nil, policy: policy)
        continue
      }

      let requestSuffix = response.requestID.map { " (request \($0))" } ?? ""
      log(
        .info,
        "\(tag) <- \(response.statusCode) in \(elapsedMilliseconds(since: started))ms\(requestSuffix)"
      )
      log(.debug, "\(tag) <- body \(loggedBody(response.body))")

      guard (200..<300).contains(response.statusCode) else {
        let error = APIError(
          status: response.statusCode,
          body: parseErrorBody(response.body),
          headers: response.headers,
          endpoint: "\(method.rawValue) \(url.absoluteString)"
        )
        guard attempt < policy.maxRetries, policy.httpStatuses.contains(response.statusCode) else {
          throw error
        }
        try await backOff(
          tag: tag,
          attempt: attempt,
          reason: String(response.statusCode),
          headers: response.headers,
          policy: policy
        )
        continue
      }

      return response
    }
    preconditionFailure("Retry loop must return or throw.")
  }

  private func decode<Value: Decodable & Sendable>(
    _ type: Value.Type,
    from response: HTTPResponse,
    endpoint: String
  ) throws -> TypeSafeResponse<Value> {
    do {
      let value = try JSONDecoder().decode(type, from: response.body)
      return TypeSafeResponse(data: value, response: response)
    } catch let error as DecodingError {
      throw APIResponseValidationError(
        status: response.statusCode,
        body: parseErrorBody(response.body),
        headers: response.headers,
        fieldPath: decodingPath(error),
        endpoint: endpoint
      )
    } catch {
      throw APIResponseValidationError(
        status: response.statusCode,
        body: parseErrorBody(response.body),
        headers: response.headers,
        fieldPath: "response",
        endpoint: endpoint
      )
    }
  }

  private func performAttempt(
    _ request: HTTPRequest,
    timeoutMilliseconds: Int
  ) async throws -> HTTPResponse {
    do {
      return try await withThrowingTaskGroup(of: AttemptResult.self) { group in
        group.addTask { [transport] in
          .response(try await transport.send(request))
        }
        group.addTask {
          try await Task.sleep(for: .milliseconds(timeoutMilliseconds))
          return .timeout
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else {
          throw APIConnectionError("The HTTP transport produced no response.")
        }
        switch first {
        case let .response(response): return response
        case .timeout: throw APITimeoutError(timeoutMilliseconds: timeoutMilliseconds)
        }
      }
    } catch is CancellationError {
      throw APIUserAbortError()
    } catch let error as APITimeoutError {
      throw error
    } catch let error as APIConnectionError {
      throw error
    } catch let error as URLError where error.code == .timedOut {
      throw APITimeoutError(timeoutMilliseconds: timeoutMilliseconds)
    } catch {
      throw APIConnectionError("Connection error: \(error)")
    }
  }

  private func backOff(
    tag: String,
    attempt: Int,
    reason: String,
    headers: [String: String]?,
    policy: RetryPolicy
  ) async throws {
    let delay = policy.delayMilliseconds(attempt: attempt, headers: headers)
    log(
      .info,
      "\(tag) retrying in \(delay)ms (retry \(attempt + 1)/\(policy.maxRetries)) after \(reason)")
    do {
      try await Task.sleep(for: .milliseconds(delay))
    } catch is CancellationError {
      throw APIUserAbortError()
    }
  }

  private func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
    guard level.rank >= logLevel.rank, logLevel != .off else { return }
    logger.log(level, message())
  }

  private func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
    let duration = start.duration(to: .now)
    return Int(duration.components.seconds * 1_000)
      + Int(duration.components.attoseconds / 1_000_000_000_000_000)
  }

  private func bodyText(_ data: Data?) -> String {
    guard let data else { return "<none>" }
    return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
  }

  private func loggedBody(_ data: Data?) -> String {
    guard logBodies else {
      guard let data else { return "<none>" }
      return "<redacted; \(data.count) bytes>"
    }
    return bodyText(data)
  }

  private func parseErrorBody(_ data: Data) -> APIErrorBody {
    guard !data.isEmpty else { return .empty }
    if let json = try? JSONDecoder().decode(JSONValue.self, from: data) { return .json(json) }
    return .text(String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>")
  }

  private func decodingPath(_ error: DecodingError) -> String {
    let path: [any CodingKey]
    switch error {
    case let .keyNotFound(key, context): path = context.codingPath + [key]
    case let .valueNotFound(_, context): path = context.codingPath
    case let .typeMismatch(_, context): path = context.codingPath
    case let .dataCorrupted(context): path = context.codingPath
    @unknown default: path = []
    }
    let rendered = path.map(\.stringValue).filter { !$0.isEmpty }.joined(separator: ".")
    return rendered.isEmpty ? "response" : rendered
  }

  private static var runtimeDescription: String {
    let os: String
    #if os(macOS)
      os = "macOS"
    #elseif os(iOS)
      os = "iOS"
    #elseif os(tvOS)
      os = "tvOS"
    #elseif os(watchOS)
      os = "watchOS"
    #elseif os(Linux)
      os = "linux"
    #else
      os = "unknown"
    #endif

    #if arch(arm64)
      let architecture = "arm64"
    #elseif arch(x86_64)
      let architecture = "x86_64"
    #else
      let architecture = "unknown"
    #endif
    return "swift/6 (\(os); \(architecture))"
  }
}
