# Changelog

## 0.6.0 - 2026-09-15

- Initial Swift 6 SDK targeting parity with the TypeSafe JavaScript and Python SDKs at `v0.6.0`.
- Added System One and Models resources, all question and answer primitives, strict response decoding,
  retries, timeout and cancellation, structured errors, logging, raw responses, and injectable HTTP
  transports.
- Added a fully mocked test suite; live API verification is pending credentials from TypeSafe.
- Added iOS/iPadOS-safe proxy authentication with fixed or async per-attempt headers, explicit
  credential redaction, HTTPS enforcement, and a default guard against embedding TypeSafe API keys
  in client applications.
- Redacted request and response bodies from debug logs by default.
