import TypeSafe

func classifySupportTicket(using client: TypeSafeClient) async throws -> String? {
  let result = try await client.systemOne(
    SystemOneRequest(
      state: "I was charged twice. Please fix this ASAP.",
      questions: [
        "category": choice(
          "What is this ticket about?",
          criteria: [
            "billing": nil,
            "technical": nil,
            "other": nil,
          ]
        )
      ]
    ))
  return result.choices["category"]?.choice
}
