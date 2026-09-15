import TypeSafe

func makeAppAuthenticatedClient(
  accessToken: @escaping @Sendable () async throws -> String,
  appVersion: String
) throws -> TypeSafeClient {
  try TypeSafeClient(
    authentication: .bearerToken { _ in try await accessToken() },
    baseURL: "https://api.example.com/typesafe",
    defaultHeaders: ["X-App-Version": appVersion]
  )
}

func classifyThroughProxy(
  using client: TypeSafeClient,
  actionID: String
) async throws -> ChoiceResponse? {
  let result = try await client.systemOne(
    SystemOneRequest(
      state: "I was charged twice. Please fix this ASAP.",
      questions: [
        "category": choice(
          "What is this ticket about?",
          criteria: ["billing": nil, "technical": nil, "other": nil]
        )
      ]
    ),
    options: RequestOptions(headers: ["X-Action-Id": actionID])
  )
  return result.choices["category"]
}
