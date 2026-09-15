import Foundation

/// Distinguishes an explicit JSON null from an omitted optional field.
public enum Nullable<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
  case value(Value)
  case null

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else {
      self = .value(try container.decode(Value.self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .value(value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

/// Optional descriptions of the true and false outcomes of a noul question.
public struct NoulCriteria: Sendable, Hashable, Codable {
  public var trueDescription: JSONValue?
  public var falseDescription: JSONValue?

  public init(true trueDescription: JSONValue? = nil, false falseDescription: JSONValue? = nil) {
    self.trueDescription = trueDescription
    self.falseDescription = falseDescription
  }

  enum CodingKeys: String, CodingKey {
    case trueDescription = "true"
    case falseDescription = "false"
  }
}

/// A yes/no question.
public struct NoulQuestion: Sendable, Hashable {
  public var instructions: JSONValue?
  /// `nil` omits the field, `.null` sends JSON null, and `.value` sends descriptions.
  public var criteria: Nullable<NoulCriteria>?

  public init(instructions: JSONValue? = nil, criteria: NoulCriteria? = nil) {
    self.instructions = instructions
    self.criteria = criteria.map(Nullable.value)
  }

  public init(instructions: JSONValue? = nil, nullableCriteria: Nullable<NoulCriteria>?) {
    self.instructions = instructions
    criteria = nullableCriteria
  }
}

/// A question that selects one named alternative.
public struct ChoiceQuestion: Sendable, Hashable {
  public var instructions: JSONValue?
  public var criteria: [String: JSONValue]

  /// Passing `nil` for `instructions` omits the field. Use `.null` to send JSON null.
  public init(instructions: JSONValue? = nil, criteria: [String: JSONValue]) {
    self.instructions = instructions
    self.criteria = criteria
  }
}

/// A question that assigns a score using an ordered rubric.
public struct ScoreQuestion: Sendable, Hashable {
  public var instructions: JSONValue?
  public var criteria: [JSONValue]

  /// Passing `nil` for `instructions` omits the field. Use `.null` to send JSON null.
  public init(instructions: JSONValue? = nil, criteria: [JSONValue]) {
    self.instructions = instructions
    self.criteria = criteria
  }
}

/// A question identified by its `type` discriminator.
public enum Question: Sendable, Hashable, Codable {
  case noul(NoulQuestion)
  case choice(ChoiceQuestion)
  case score(ScoreQuestion)
  /// A future question type not known by this SDK version.
  case custom(type: String, fields: [String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    let typeKey = DynamicCodingKey("type")
    let type = try container.decode(String.self, forKey: typeKey)
    let instructions = try container.decodeIfPresent(
      JSONValue.self, forKey: DynamicCodingKey("instructions"))

    switch type {
    case "noul":
      let criteriaKey = DynamicCodingKey("criteria")
      let criteria: Nullable<NoulCriteria>?
      if !container.contains(criteriaKey) {
        criteria = nil
      } else if try container.decodeNil(forKey: criteriaKey) {
        criteria = .null
      } else {
        criteria = .value(try container.decode(NoulCriteria.self, forKey: criteriaKey))
      }
      self = .noul(.init(instructions: instructions, nullableCriteria: criteria))
    case "choice":
      let criteria = try container.decode(
        [String: JSONValue].self, forKey: DynamicCodingKey("criteria"))
      self = .choice(.init(instructions: instructions, criteria: criteria))
    case "score":
      let criteria = try container.decode([JSONValue].self, forKey: DynamicCodingKey("criteria"))
      self = .score(.init(instructions: instructions, criteria: criteria))
    default:
      let raw = try JSONValue(from: decoder)
      guard case var .object(fields) = raw else {
        throw DecodingError.dataCorruptedError(
          forKey: typeKey,
          in: container,
          debugDescription: "Question must be a JSON object."
        )
      }
      fields.removeValue(forKey: "type")
      self = .custom(type: type, fields: fields)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    switch self {
    case let .noul(question):
      try container.encode("noul", forKey: DynamicCodingKey("type"))
      try container.encodeIfPresent(question.instructions, forKey: DynamicCodingKey("instructions"))
      try container.encodeIfPresent(question.criteria, forKey: DynamicCodingKey("criteria"))
    case let .choice(question):
      try container.encode("choice", forKey: DynamicCodingKey("type"))
      try container.encodeIfPresent(question.instructions, forKey: DynamicCodingKey("instructions"))
      try container.encode(question.criteria, forKey: DynamicCodingKey("criteria"))
    case let .score(question):
      try container.encode("score", forKey: DynamicCodingKey("type"))
      try container.encodeIfPresent(question.instructions, forKey: DynamicCodingKey("instructions"))
      try container.encode(question.criteria, forKey: DynamicCodingKey("criteria"))
    case let .custom(type, fields):
      for (name, value) in fields where name != "type" {
        try container.encode(value, forKey: DynamicCodingKey(name))
      }
      try container.encode(type, forKey: DynamicCodingKey("type"))
    }
  }
}

/// Create a yes/no question. The default instructions value is explicit JSON null, matching the
/// JavaScript SDK's `noul()` builder.
public func noul(
  _ instructions: JSONValue = .null,
  criteria: NoulCriteria? = nil
) -> Question {
  .noul(.init(instructions: instructions, criteria: criteria))
}

public func noul(_ instructions: String, criteria: NoulCriteria? = nil) -> Question {
  noul(.string(instructions), criteria: criteria)
}

/// Create a yes/no question with an explicit nullable criteria field.
public func noul(
  _ instructions: JSONValue,
  nullableCriteria: Nullable<NoulCriteria>
) -> Question {
  .noul(.init(instructions: instructions, nullableCriteria: nullableCriteria))
}

public func noul(
  _ instructions: String,
  nullableCriteria: Nullable<NoulCriteria>
) -> Question {
  noul(.string(instructions), nullableCriteria: nullableCriteria)
}

/// Create a choice question. Nil criterion descriptions are encoded as JSON null.
public func choice(
  _ instructions: JSONValue,
  criteria: [String: JSONValue?]
) -> Question {
  var normalized: [String: JSONValue] = [:]
  normalized.reserveCapacity(criteria.count)
  for (name, description) in criteria {
    normalized[name] = description ?? .null
  }
  return .choice(.init(instructions: instructions, criteria: normalized))
}

public func choice(_ instructions: String, criteria: [String: JSONValue?]) -> Question {
  choice(.string(instructions), criteria: criteria)
}

/// Create a score question with descriptions ordered from score zero upward.
public func score(_ instructions: JSONValue, criteria: [JSONValue]) -> Question {
  .score(.init(instructions: instructions, criteria: criteria))
}

public func score(_ instructions: String, criteria: [JSONValue]) -> Question {
  score(.string(instructions), criteria: criteria)
}
