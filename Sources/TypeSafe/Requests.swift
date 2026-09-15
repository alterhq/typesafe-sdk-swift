import Foundation

/// State and named questions for `systemOne`.
public struct SystemOneRequest: Sendable, Hashable {
  public var state: JSONValue
  public var questions: [String: Question]
  public var model: String?
  /// Forward-compatible top-level fields. Reserved fields are always taken from the typed values.
  public var additionalFields: [String: JSONValue]

  public init(
    state: JSONValue,
    questions: [String: Question],
    model: String? = nil,
    additionalFields: [String: JSONValue] = [:]
  ) {
    self.state = state
    self.questions = questions
    self.model = model
    self.additionalFields = additionalFields
  }

  public init(
    state: String,
    questions: [String: Question],
    model: String? = nil,
    additionalFields: [String: JSONValue] = [:]
  ) {
    self.init(
      state: .string(state),
      questions: questions,
      model: model,
      additionalFields: additionalFields
    )
  }
}

struct SystemOnePayload: Encodable {
  let request: SystemOneRequest
  let resolvedModel: String

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for (name, value) in request.additionalFields
    where name != "state" && name != "questions" && name != "model" {
      try container.encode(value, forKey: DynamicCodingKey(name))
    }
    try container.encode(request.state, forKey: DynamicCodingKey("state"))
    try container.encode(request.questions, forKey: DynamicCodingKey("questions"))
    try container.encode(resolvedModel, forKey: DynamicCodingKey("model"))
  }
}
