import XCTest

@testable import TypeSafe

final class WireFormatTests: XCTestCase {
  func testJSONValueRoundTripsAllShapes() throws {
    let value: JSONValue = [
      "string": "hello",
      "integer": 1,
      "number": 1.5,
      "bool": true,
      "array": [nil, false, ["nested": "yes"]],
      "null": nil,
    ]
    let encoded = try JSONEncoder.sorted.encode(value)
    XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: encoded), value)
  }

  func testQuestionBuildersEncodeDocumentedWireFormat() throws {
    let questions: [String: Question] = [
      "binary": noul("Is it billing?", criteria: .init(true: "yes", false: nil)),
      "category": choice("Category?", criteria: ["billing": nil, "other": "anything else"]),
      "quality": score(nil, criteria: ["bad", ["label": "good"]]),
      "default": noul(),
    ]
    let data = try JSONEncoder.sorted.encode(questions)
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    let binary = try XCTUnwrap(json["binary"] as? [String: Any])
    XCTAssertEqual(binary["type"] as? String, "noul")
    XCTAssertEqual(binary["instructions"] as? String, "Is it billing?")
    let binaryCriteria = try XCTUnwrap(binary["criteria"] as? [String: Any])
    XCTAssertEqual(binaryCriteria["true"] as? String, "yes")
    XCTAssertNil(binaryCriteria["false"])

    let category = try XCTUnwrap(json["category"] as? [String: Any])
    let categoryCriteria = try XCTUnwrap(category["criteria"] as? [String: Any])
    XCTAssertTrue(categoryCriteria["billing"] is NSNull)

    let quality = try XCTUnwrap(json["quality"] as? [String: Any])
    XCTAssertTrue(quality["instructions"] is NSNull)
    XCTAssertEqual((quality["criteria"] as? [Any])?.first as? String, "bad")

    let defaultQuestion = try XCTUnwrap(json["default"] as? [String: Any])
    XCTAssertTrue(defaultQuestion["instructions"] is NSNull)
    XCTAssertNil(defaultQuestion["criteria"])
  }

  func testOmittedInstructionsRemainOmitted() throws {
    let question = Question.noul(.init(instructions: nil, criteria: nil))
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: JSONEncoder.sorted.encode(question)) as? [String: Any]
    )
    XCTAssertEqual(object["type"] as? String, "noul")
    XCTAssertNil(object["instructions"])
  }

  func testNoulCriteriaCanBeOmittedOrExplicitlyNull() throws {
    let questions = [
      "omitted": noul("q"),
      "null": noul("q", nullableCriteria: .null),
    ]
    let object = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: JSONEncoder.sorted.encode(questions))
        as? [String: [String: Any]]
    )
    XCTAssertNil(object["omitted"]?["criteria"])
    XCTAssertTrue(object["null"]?["criteria"] is NSNull)

    let decoded = try JSONDecoder().decode(
      [String: Question].self, from: JSONEncoder.sorted.encode(questions))
    guard case let .noul(nullQuestion)? = decoded["null"] else { return XCTFail("Expected noul") }
    XCTAssertEqual(nullQuestion.criteria, .null)
  }

  func testCustomQuestionRoundTripsFutureFields() throws {
    let original = Question.custom(type: "future", fields: ["enabled": true, "weight": 2])
    let data = try JSONEncoder.sorted.encode(original)
    XCTAssertEqual(try JSONDecoder().decode(Question.self, from: data), original)
  }

  func testAllAnswerTypesDecodeAndScoreKeysBecomeIntegers() throws {
    let response = try JSONDecoder().decode(SystemOneResponse.self, from: Data(systemOneJSON.utf8))
    XCTAssertEqual(response.model, "jev-latest")
    XCTAssertEqual(response.nouls["binary"]?.noul, 0.75)
    XCTAssertEqual(response.choices["category"]?.choice, "billing")
    XCTAssertEqual(response.scores["quality"]?.score, 1.6)
    XCTAssertEqual(response.scores["quality"]?.probabilities[2], 0.7)
    XCTAssertEqual(response.scores["quality"]?.legend[2], ["label": "great"])
    XCTAssertEqual(response.usage, Usage(inputTokens: 12, outputTokens: 4))
  }

  func testUnknownAnswersArePreserved() throws {
    let data = Data(
      #"{"model":"m","answers":{"q":{"type":"future","value":7}},"usage":{"input_tokens":1,"output_tokens":2}}"#
        .utf8)
    let response = try JSONDecoder().decode(SystemOneResponse.self, from: data)
    guard case let .unknown(type, fields)? = response.answers["q"] else {
      return XCTFail("Expected unknown answer")
    }
    XCTAssertEqual(type, "future")
    XCTAssertEqual(fields["value"], 7)
  }

  func testEveryAnswerCaseRoundTrips() throws {
    let answers: [Answer] = [
      .noul(.init(noul: 0.4)),
      .choice(.init(choice: "a", confidence: 0.7, probabilities: ["a": 0.7, "b": 0.3])),
      .score(
        .init(
          score: 1.2, confidence: 0.8, legend: [0: "low", 1: "high"],
          probabilities: [0: 0.2, 1: 0.8])),
      .unknown(type: "future", fields: ["value": 1]),
    ]
    for answer in answers {
      let data = try JSONEncoder.sorted.encode(answer)
      XCTAssertEqual(try JSONDecoder().decode(Answer.self, from: data), answer)
    }
  }
}
