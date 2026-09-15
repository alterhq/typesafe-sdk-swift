import Foundation

@testable import TypeSafe

enum MockTransportFailure: Error, Sendable {
  case disconnected
}

actor MockTransport: HTTPTransport {
  enum Step: Sendable {
    case response(HTTPResponse)
    case failure(MockTransportFailure)
    case delayed(HTTPResponse, Duration)
    case hang
  }

  private var steps: [Step]
  private var captured: [HTTPRequest] = []

  init(_ steps: [Step]) {
    self.steps = steps
  }

  func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    captured.append(request)
    guard !steps.isEmpty else { throw MockTransportFailure.disconnected }
    let step = steps.removeFirst()
    switch step {
    case let .response(response):
      return response
    case let .failure(error):
      throw error
    case let .delayed(response, duration):
      try await Task.sleep(for: duration)
      return response
    case .hang:
      try await Task.sleep(for: .seconds(3_600))
      throw MockTransportFailure.disconnected
    }
  }

  func requests() -> [HTTPRequest] { captured }
}

func jsonResponse(
  _ json: String,
  status: Int = 200,
  headers: [String: String] = ["content-type": "application/json"]
) -> HTTPResponse {
  HTTPResponse(statusCode: status, headers: headers, body: Data(json.utf8))
}

let modelsJSON =
  #"{"models":[{"name":"jev-latest","description":"Latest model","release_date":"2026-09-15"}]}"#

let systemOneJSON = #"""
  {
      "model":"jev-latest",
      "answers":{
          "binary":{"type":"noul","noul":0.75},
          "category":{"type":"choice","choice":"billing","confidence":0.9,"probabilities":{"billing":0.9,"other":0.1}},
          "quality":{"type":"score","score":1.6,"confidence":0.8,"legend":{"0":"bad","1":"ok","2":{"label":"great"}},"probabilities":{"0":0.1,"1":0.2,"2":0.7}}
      },
      "usage":{"input_tokens":12,"output_tokens":4}
  }
  """#

func header(_ name: String, in request: HTTPRequest) -> String? {
  request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}
