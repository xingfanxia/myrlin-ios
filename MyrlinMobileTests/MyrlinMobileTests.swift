import XCTest
@testable import MyrlinMobile

final class MyrlinMobileTests: XCTestCase {
    func testStreamMessageDecodeAssistant() throws {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"text","text":"Hello!"}],"role":"assistant"}}
        """
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json.data(using: .utf8)!)
        if case .assistantText(let content) = msg.type {
            XCTAssertEqual(content, "Hello!")
        } else {
            XCTFail("Expected assistantText")
        }
    }

    func testStreamMessageDecodeSystem() throws {
        let json = """
        {"type":"system","subtype":"stderr","content":"Error: something went wrong"}
        """
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json.data(using: .utf8)!)
        if case .systemMessage(let content, let subtype) = msg.type {
            XCTAssertEqual(subtype, "stderr")
            XCTAssertTrue(content.contains("Error"))
        } else {
            XCTFail("Expected systemMessage")
        }
    }

    func testStreamMessageDecodeStats() throws {
        let json = """
        {"type":"result","total_input_tokens":1234,"total_output_tokens":567,"total_cost":0.025}
        """
        let msg = try JSONDecoder().decode(StreamMessage.self, from: json.data(using: .utf8)!)
        if case .stats(let input, let output, let cost) = msg.type {
            XCTAssertEqual(input, 1234)
            XCTAssertEqual(output, 567)
            XCTAssertEqual(cost, 0.025, accuracy: 0.001)
        } else {
            XCTFail("Expected stats")
        }
    }
}
