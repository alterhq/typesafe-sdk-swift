# Upstream parity

This package targets the TypeSafe JavaScript and Python SDK `v0.6.0` contract. The API key is not
available during development, so every row is verified against the documented wire format using
mock transports. A live smoke test remains the first step once TypeSafe provides credentials.

| Capability | Swift status | Verification |
|---|---|---|
| `POST /v1/systemone` | Complete | Serialized request and decoded fixture tests |
| `GET /v1/models` | Complete | Request, response, and malformed-shape tests |
| Noul, choice, and score questions | Complete | Builder, explicit-null, and round-trip tests |
| Noul, choice, and score answers | Complete | Discriminator and round-trip tests |
| Structured JSON state/descriptions | Complete | Full `JSONValue` round-trip test |
| Default/per-call model | Complete | Captured request tests |
| Forward-compatible extra body fields | Complete | Captured request tests |
| Future question/answer discriminators | Complete | Lossless round-trip tests |
| API key and environment configuration | Complete | Precedence, blank, and missing-value tests |
| App-authenticated proxy mode without TypeSafe key | Complete | Alter-style proxy request test |
| Static and per-attempt dynamic auth headers | Complete | Header precedence and retry-refresh tests |
| Mobile direct-key safety guard | Complete | Simulated client-platform configuration tests |
| HTTPS-by-default base URLs | Complete | Remote, loopback, and development opt-in tests |
| Protected/default/per-call headers | Complete | Case-insensitive captured-header tests |
| SDK and runtime identification headers | Complete | Captured-header tests |
| Per-attempt timeout | Complete | Hanging mock transport test |
| Caller cancellation | Complete | Native Swift task-cancellation test |
| Retryable HTTP responses | Complete | Scripted 503-to-success test |
| Connection and timeout retries | Complete | Scripted failure and timeout tests |
| Exponential backoff and jitter | Complete | Deterministic delay tests |
| `retry-after-ms` and `Retry-After` | Complete | Parsing, priority, and cap tests |
| Per-call retry overrides | Complete | Retry-disable test |
| Status-classified API errors | Complete | 400/401/403/404/422/429/5xx tests |
| Request IDs and rate-limit delay | Complete | Error and successful metadata tests |
| Structured validation error messages | Complete | FastAPI-style error fixture test |
| Strict successful-response validation | Complete | Malformed 2xx fixture test |
| Raw successful HTTP response access | Complete | Non-JSON raw response test |
| Logging and credential redaction | Complete | Redaction test |
| Request/response body privacy | Complete | Bodies redacted by default; explicit debug opt-in |
| Default `URLSession` transport | Complete | Mock `URLProtocol` test; no network required |
| Swift 6 concurrency safety | Complete | Strict build with warnings as errors |

## Idiomatic Swift adaptations

- Swift task cancellation replaces JavaScript `AbortSignal`.
- `systemOneWithResponse`, `systemOneRawResponse`, `listWithResponse`, and `listRawResponse` replace
  the JavaScript `APIPromise` helpers.
- `APIError.Kind` replaces JavaScript's error subclasses while retaining status, parsed body,
  headers, request ID, and retry delay in one catchable value.
- A heterogeneous Swift dictionary cannot reproduce TypeScript conditional mapped return types.
  `SystemOneResponse.answers` therefore contains a discriminated `Answer` enum, with `nouls`,
  `choices`, and `scores` filtered accessors similar to the Python SDK.
- Unknown answer types are preserved as `.unknown` rather than discarded, retaining more raw data
  while remaining forward-compatible.
- `TypeSafeAuthentication` allows mobile apps to reuse all typed requests and responses through an
  app-authenticated proxy without shipping the TypeSafe API key.

## Credentialed validation checklist

When credentials become available:

1. Call `models.listWithResponse()` and confirm the model metadata schema and identification headers.
2. Submit one noul, choice, and score question in a single `systemOneWithResponse` call.
3. Confirm integer score legend/probability keys, usage fields, and request ID behavior.
4. Exercise one safe validation failure to confirm the production error-body shape.
5. Run the prepared opt-in integration test with
   `TYPESAFE_RUN_LIVE_TESTS=1 TYPESAFE_API_KEY=... swift test --filter LiveIntegrationTests` and
   record the API/model versions.
