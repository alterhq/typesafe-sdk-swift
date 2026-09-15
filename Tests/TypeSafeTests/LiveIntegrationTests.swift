import Foundation
import TypeSafe
import XCTest

final class LiveIntegrationTests: XCTestCase {
  func testDocumentedAPIContract() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TYPESAFE_RUN_LIVE_TESTS"] == "1" else {
      throw XCTSkip("Set TYPESAFE_RUN_LIVE_TESTS=1 to enable credentialed API tests.")
    }
    guard environment[TypeSafeEnvironment.apiKey]?.isEmpty == false else {
      throw XCTSkip("Set TYPESAFE_API_KEY to enable credentialed API tests.")
    }

    let client = try TypeSafeClient(logLevel: .info)
    let models = try await client.models.listWithResponse()
    XCTAssertFalse(models.data.isEmpty)

    let result = try await client.systemOneWithResponse(
      SystemOneRequest(
        state: "I was charged twice. Please help.",
        questions: [
          "billing": noul("Is this about billing?"),
          "category": choice("What is this about?", criteria: ["billing": nil, "other": nil]),
          "urgency": score("How urgent is this?", criteria: ["not urgent", "urgent"]),
        ]
      ))
    XCTAssertNotNil(result.data.nouls["billing"])
    XCTAssertNotNil(result.data.choices["category"])
    XCTAssertNotNil(result.data.scores["urgency"])
    XCTAssertFalse(result.data.model.isEmpty)
  }
}
