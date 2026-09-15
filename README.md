# TypeSafe AI Swift SDK

A dependency-free Swift 6 client for the [TypeSafe AI API](https://docs.typesafe.ai/api),
ported from the official JavaScript and Python SDKs.

The package supports macOS 13+, iOS/iPadOS 16+, tvOS 16+, and watchOS 9+. It uses strict Swift 6
concurrency, `URLSession`, `Codable`, and native task cancellation.

> [!IMPORTANT]
> The recommended production architecture on every platform is to route SDK requests through your
> authenticated backend. Keep the TypeSafe API key in server-side secret storage. Direct API-key
> mode in this Swift SDK is intended only for quick local development and debugging.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/typesafe-ai/typesafe-sdk-swift.git", from: "0.6.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "TypeSafe", package: "typesafe-sdk-swift"),
    ]),
]
```

## Recommended setup: authenticated backend proxy

Point the typed client at your own backend in production on macOS, iOS/iPadOS, tvOS, watchOS, and
other supported platforms. The application authenticates with its normal session credentials; only
the backend holds and uses the TypeSafe API key.

Pass the application's access token through an async provider. The SDK resolves it again for every
retry, so the provider can refresh an expired session:

```swift
import TypeSafe

func makeTypeSafeClient(
    accessToken: @escaping @Sendable () async throws -> String,
    appVersion: String
) throws -> TypeSafeClient {
    try TypeSafeClient(
        authentication: .bearerToken { _ in
            try await accessToken()
        },
        baseURL: "https://api.example.com/typesafe",
        defaultHeaders: ["X-App-Version": appVersion]
    )
}

let client = try makeTypeSafeClient(
    accessToken: { try await appSession.validAccessToken() },
    appVersion: appVersion
)

let result = try await client.systemOne(
    SystemOneRequest(
        state: "I was charged twice. Please fix this ASAP.",
        questions: [
            "category": choice(
                "What is this ticket about?",
                criteria: ["billing": nil, "technical": nil, "other": nil]
            ),
        ]
    ),
    options: RequestOptions(headers: [
        "X-Action-Id": actionID,
    ])
)

if let category = result.choices["category"] {
    print(category.choice, category.confidence)
}
```

Arbitrary authentication schemes are supported when a backend needs multiple headers or request
signing:

```swift
let client = try TypeSafeClient(
    authentication: .headers(
        sensitiveHeaderNames: ["X-App-Token"]
    ) { context in
        [
            "X-App-Token": try await tokenStore.token(),
            "X-Signature": try await signer.sign(
                method: context.method.rawValue,
                url: context.url
            ),
        ]
    },
    baseURL: "https://api.example.com/typesafe"
)
```

Use `.unauthenticated` when `URLSession` supplies a secure cookie. Supplying any explicit
`authentication` strategy bypasses `TYPESAFE_API_KEY`, even if that variable exists in the developer
environment.

Header precedence is case-insensitive: `defaultHeaders`, then per-call `RequestOptions.headers`, then
the authentication provider, followed by SDK-managed protocol headers. All headers returned by the
authentication provider are redacted from debug logs. `sensitiveHeaderNames` can additionally mark
conditional headers that may originate in another layer. Request and response bodies are also
redacted unless `logBodies: true` is set.

The backend proxy should:

1. Authenticate and authorize the incoming app request.
2. Accept only the intended SDK routes, currently `/v1/systemone` and `/v1/models`.
3. Forward the JSON body to the matching `https://api.typesafe.ai` route.
4. Replace the app's authentication header with `Authorization: Bearer <TYPESAFE_API_KEY>` on the
   server-to-server request.
5. Return the upstream status, JSON body, and useful headers such as `X-TypeSafe-Request-ID`.

The backend must never return or log the TypeSafe API key, and should not blindly forward arbitrary
client headers upstream.

## Direct API access for local development

For a quick local experiment or debugger session, set `TYPESAFE_API_KEY` and connect directly:

```swift
let client = try TypeSafeClient()
let models = try await client.models.list()
```

Do not ship or deploy this configuration. Direct API-key initialization on iOS/iPadOS, tvOS, and
watchOS is blocked by default. `dangerouslyAllowAPIKeyInClient: true` exists only for controlled
development builds.

The direct-development client reads these environment variables when an explicit option is absent:

| Variable | Purpose | Default |
|---|---|---|
| `TYPESAFE_API_KEY` | Development/debug Bearer API key | Required in direct mode |
| `TYPESAFE_BASE_URL` | API root | `https://api.typesafe.ai` |
| `TYPESAFE_DEFAULT_MODEL` | Default request model | `jev-latest` |
| `TYPESAFE_LOG_LEVEL` | `debug`, `info`, `warn`, `error`, or `off` | `warn` |

Explicit initializer values take precedence over the environment. Blank environment values are
ignored. Remote base URLs require HTTPS by default; loopback HTTP is allowed, and other development
HTTP endpoints require `allowsInsecureHTTP: true`.

## Question primitives

All instructions, state, and criterion descriptions accept `JSONValue`, which supports string,
integer, floating-point, boolean, object, array, and null literals.

```swift
let questions: [String: Question] = [
    "relevant": noul(
        "Is this relevant?",
        criteria: NoulCriteria(true: "directly related", false: "unrelated")
    ),
    "category": choice(
        ["task": "Classify the request"],
        criteria: ["billing": nil, "technical": nil, "other": nil]
    ),
    "quality": score(
        "Rate the response quality",
        criteria: ["poor", "acceptable", ["quality": "excellent"]]
    ),
]
```

`score` criteria are ordered from zero and require at least two entries. Empty question maps and
short score rubrics fail before the transport is called.

For noul criteria, `nil` omits the field while `nullableCriteria: .null` sends explicit JSON null:

```swift
let omitted = noul("Question")
let explicitNull = noul("Question", nullableCriteria: .null)
```

## Models

```swift
let models = try await client.models.list()
for model in models {
    print(model.name, model.description, model.releaseDate)
}
```

## Request options and retries

The default timeout is 10 seconds per attempt. The client retries HTTP 408, 429, and 5xx responses,
connection failures, and timeouts twice with capped exponential backoff and jitter. Valid
`retry-after-ms` and `Retry-After` headers take precedence.

```swift
let retry = try RetryPolicy(
    maxRetries: 3,
    backoffInitialMilliseconds: 250,
    backoffMaxMilliseconds: 4_000,
    httpStatuses: [408, 409, 429, 500, 502, 503, 504]
)

let client = try TypeSafeClient(
    authentication: .bearerToken { _ in
        try await appSession.validAccessToken()
    },
    baseURL: "https://api.example.com/typesafe",
    retry: retry
)

let result = try await client.systemOne(
    SystemOneRequest(state: "...", questions: questions),
    options: RequestOptions(
        timeoutMilliseconds: 5_000,
        retry: RetryPolicyOverrides(maxRetries: 1),
        headers: ["X-Trace-ID": "trace-123"]
    )
)
```

Cancel the calling `Task` to cancel the active HTTP request or pending backoff. Cancellation is
reported as `APIUserAbortError`; attempt timeouts use `APITimeoutError`.

## Errors

All SDK errors conform to `TypeSafeError`:

- `TypeSafeConfigurationError` for missing or invalid configuration and request input.
- `APIError` for non-2xx responses. Inspect `status`, `kind`, `body`, `headers`, `requestID`, and
  `retryAfterMilliseconds`.
- `APIConnectionError` for transport failures.
- `APITimeoutError` for attempt timeouts.
- `APIUserAbortError` for caller cancellation.
- `APIResponseValidationError` for malformed successful responses, including the failing field path.

```swift
do {
    _ = try await client.models.list()
} catch let error as APIError where error.kind == .rateLimit {
    print("Retry after:", error.retryAfterMilliseconds as Any)
} catch let error as any TypeSafeError {
    print(error)
}
```

## Raw HTTP responses

Use the `WithResponse` variants when decoded data and HTTP metadata are both needed:

```swift
let result = try await client.systemOneWithResponse(request)
print(result.requestID as Any)
print(result.response.statusCode)
```

Use `systemOneRawResponse` or `models.listRawResponse` to retain a successful body without decoding
it. Non-2xx responses still throw `APIError` after retries.

## Testing without an API key

Implement `HTTPTransport` and inject it into `TypeSafeClient`. The repository's test suite uses a
scripted actor-backed transport, so it tests serialization, decoding, retry behavior, timeouts,
cancellation, and errors without making network requests.

```swift
struct FixtureTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["content-type": "application/json"],
            body: Data(#"{"models":[]}"#.utf8)
        )
    }
}

let client = try TypeSafeClient(
    authentication: .unauthenticated,
    transport: FixtureTransport()
)
```

Run the suite with:

```console
swift test
```

Live integration testing is intentionally deferred until a TypeSafe API key is available.

## Official documentation

Learn what TypeSafe can do in the [TypeSafe docs](https://docs.typesafe.ai/). See the other official
SDKs for [Python](https://github.com/typesafe-ai/typesafe-sdk-python) and
[TypeScript/JavaScript](https://github.com/typesafe-ai/typesafe-sdk-js).

## License

MIT. See [LICENSE](LICENSE).
