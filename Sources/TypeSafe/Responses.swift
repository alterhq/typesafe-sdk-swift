import Foundation

/// A yes/no answer represented as the probability of true.
public struct NoulResponse: Sendable, Hashable, Codable {
  public let noul: Double

  public init(noul: Double) { self.noul = noul }
}

/// A selected label and its probabilities.
public struct ChoiceResponse: Sendable, Hashable, Codable {
  public let choice: String
  public let confidence: Double
  public let probabilities: [String: Double]

  public init(choice: String, confidence: Double, probabilities: [String: Double]) {
    self.choice = choice
    self.confidence = confidence
    self.probabilities = probabilities
  }
}

/// An expected score with its rubric and probabilities.
public struct ScoreResponse: Sendable, Hashable, Codable {
  public let score: Double
  public let confidence: Double
  public let legend: [Int: JSONValue]
  public let probabilities: [Int: Double]

  public init(
    score: Double,
    confidence: Double,
    legend: [Int: JSONValue],
    probabilities: [Int: Double]
  ) {
    self.score = score
    self.confidence = confidence
    self.legend = legend
    self.probabilities = probabilities
  }

  enum CodingKeys: String, CodingKey {
    case score, confidence, legend, probabilities
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    score = try container.decode(Double.self, forKey: .score)
    confidence = try container.decode(Double.self, forKey: .confidence)
    let wireLegend = try container.decode([String: JSONValue].self, forKey: .legend)
    let wireProbabilities = try container.decode([String: Double].self, forKey: .probabilities)
    legend = try Self.integerKeys(wireLegend, codingPath: decoder.codingPath + [CodingKeys.legend])
    probabilities = try Self.integerKeys(
      wireProbabilities, codingPath: decoder.codingPath + [CodingKeys.probabilities])
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(score, forKey: .score)
    try container.encode(confidence, forKey: .confidence)
    try container.encode(
      Dictionary(uniqueKeysWithValues: legend.map { (String($0.key), $0.value) }), forKey: .legend)
    try container.encode(
      Dictionary(uniqueKeysWithValues: probabilities.map { (String($0.key), $0.value) }),
      forKey: .probabilities)
  }

  private static func integerKeys<Value>(
    _ values: [String: Value],
    codingPath: [any CodingKey]
  ) throws -> [Int: Value] {
    var result: [Int: Value] = [:]
    result.reserveCapacity(values.count)
    for (key, value) in values {
      guard let integer = Int(key) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: codingPath,
            debugDescription: "Expected integer score key, got \"\(key)\"."
          ))
      }
      result[integer] = value
    }
    return result
  }
}

/// An answer identified by its `type` discriminator.
public enum Answer: Sendable, Hashable, Codable {
  case noul(NoulResponse)
  case choice(ChoiceResponse)
  case score(ScoreResponse)
  /// A future answer type retained without losing its payload.
  case unknown(type: String, fields: [String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let typeKey = DynamicCodingKey("type")
    let type = try container.decode(String.self, forKey: typeKey)
    switch type {
    case "noul":
      self = .noul(try NoulResponse(from: decoder))
    case "choice":
      self = .choice(try ChoiceResponse(from: decoder))
    case "score":
      self = .score(try ScoreResponse(from: decoder))
    default:
      let raw = try JSONValue(from: decoder)
      guard case var .object(fields) = raw else {
        throw DecodingError.dataCorruptedError(
          forKey: typeKey,
          in: container,
          debugDescription: "Answer must be a JSON object."
        )
      }
      fields.removeValue(forKey: "type")
      self = .unknown(type: type, fields: fields)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    switch self {
    case let .noul(answer):
      try container.encode("noul", forKey: DynamicCodingKey("type"))
      try container.encode(answer.noul, forKey: DynamicCodingKey("noul"))
    case let .choice(answer):
      try container.encode("choice", forKey: DynamicCodingKey("type"))
      try container.encode(answer.choice, forKey: DynamicCodingKey("choice"))
      try container.encode(answer.confidence, forKey: DynamicCodingKey("confidence"))
      try container.encode(answer.probabilities, forKey: DynamicCodingKey("probabilities"))
    case let .score(answer):
      try container.encode("score", forKey: DynamicCodingKey("type"))
      try container.encode(answer.score, forKey: DynamicCodingKey("score"))
      try container.encode(answer.confidence, forKey: DynamicCodingKey("confidence"))
      let legend = Dictionary(
        uniqueKeysWithValues: answer.legend.map { (String($0.key), $0.value) })
      let probabilities = Dictionary(
        uniqueKeysWithValues: answer.probabilities.map { (String($0.key), $0.value) })
      try container.encode(legend, forKey: DynamicCodingKey("legend"))
      try container.encode(probabilities, forKey: DynamicCodingKey("probabilities"))
    case let .unknown(type, fields):
      for (name, value) in fields where name != "type" {
        try container.encode(value, forKey: DynamicCodingKey(name))
      }
      try container.encode(type, forKey: DynamicCodingKey("type"))
    }
  }
}

/// Token usage for a System One request.
public struct Usage: Sendable, Hashable, Codable {
  public let inputTokens: Int
  public let outputTokens: Int

  public init(inputTokens: Int, outputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
  }
}

/// Answers keyed by question name, with model and usage metadata.
public struct SystemOneResponse: Sendable, Hashable, Codable {
  public let model: String
  public let answers: [String: Answer]
  public let usage: Usage

  public init(model: String, answers: [String: Answer], usage: Usage) {
    self.model = model
    self.answers = answers
    self.usage = usage
  }

  public var nouls: [String: NoulResponse] {
    answers.compactMapValues { answer in
      guard case let .noul(value) = answer else { return nil }
      return value
    }
  }

  public var choices: [String: ChoiceResponse] {
    answers.compactMapValues { answer in
      guard case let .choice(value) = answer else { return nil }
      return value
    }
  }

  public var scores: [String: ScoreResponse] {
    answers.compactMapValues { answer in
      guard case let .score(value) = answer else { return nil }
      return value
    }
  }
}

/// Metadata for a model available to the account.
public struct ModelCard: Sendable, Hashable, Codable {
  public let name: String
  public let description: String
  public let releaseDate: String

  public init(name: String, description: String, releaseDate: String) {
    self.name = name
    self.description = description
    self.releaseDate = releaseDate
  }

  enum CodingKeys: String, CodingKey {
    case name, description
    case releaseDate = "release_date"
  }
}
