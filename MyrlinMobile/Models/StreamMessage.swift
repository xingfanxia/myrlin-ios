import Foundation

/// Represents a single message from the claude stream-json output format.
/// Each line from claude's stdout is parsed into one of these cases.
struct StreamMessage: Identifiable {
    let id: UUID = UUID()
    let type: MessageType
    let timestamp: Date = Date()

    enum MessageType {
        case assistantText(content: String)
        case toolUse(name: String, inputJSON: String)
        case toolResult(content: String, toolUseId: String?)
        case thinking(content: String)
        case userMessage(content: String)
        case systemMessage(content: String, subtype: String)
        case stats(inputTokens: Int, outputTokens: Int, cost: Double)
        case raw(json: [String: Any])
    }
}

extension StreamMessage: Decodable {
    enum CodingKeys: String, CodingKey {
        case type, role, content, subtype
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let msgType = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"

        switch msgType {
        case "assistant":
            let content = try Self.extractAssistantContent(from: decoder)
            self.type = .assistantText(content: content)

        case "human", "user":
            let content = try Self.extractTextContent(from: decoder)
            self.type = .userMessage(content: content)

        case "tool_use":
            let name = try Self.extractToolName(from: decoder)
            let input = try Self.extractToolInput(from: decoder)
            self.type = .toolUse(name: name, inputJSON: input)

        case "tool_result":
            let content = try Self.extractTextContent(from: decoder)
            self.type = .toolResult(content: content, toolUseId: nil)

        case "thinking":
            let content = try Self.extractTextContent(from: decoder)
            self.type = .thinking(content: content)

        case "result":
            let stats = try Self.extractStats(from: decoder)
            self.type = stats

        case "system":
            let content = try Self.extractTextContent(from: decoder)
            let subtype = try container.decodeIfPresent(String.self, forKey: .subtype) ?? "info"
            self.type = .systemMessage(content: content, subtype: subtype)

        default:
            self.type = .raw(json: [:])
        }
    }

    // MARK: - Content Extractors

    private static func extractAssistantContent(from decoder: Decoder) throws -> String {
        // claude stream-json: {type:"assistant", message:{content:[{type:"text",text:"..."}]}}
        struct Outer: Decodable {
            struct Msg: Decodable {
                struct Block: Decodable {
                    let type: String
                    let text: String?
                }
                let content: [Block]?
                let role: String?
            }
            let message: Msg?
            // Also handle flat content string
            let content: String?
        }
        let outer = try Outer(from: decoder)
        if let blocks = outer.message?.content {
            return blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
        return outer.content ?? ""
    }

    private static func extractTextContent(from decoder: Decoder) throws -> String {
        struct Outer: Decodable { let content: String? }
        let outer = try Outer(from: decoder)
        return outer.content ?? ""
    }

    private static func extractToolName(from decoder: Decoder) throws -> String {
        struct Outer: Decodable { let name: String? }
        return (try? Outer(from: decoder).name) ?? "unknown_tool"
    }

    private static func extractToolInput(from decoder: Decoder) throws -> String {
        struct Outer: Decodable { let input: AnyCodable? }
        if let input = (try? Outer(from: decoder).input) {
            if let data = try? JSONEncoder().encode(input),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        return "{}"
    }

    private static func extractStats(from decoder: Decoder) throws -> MessageType {
        struct Outer: Decodable {
            let total_input_tokens: Int?
            let total_output_tokens: Int?
            let total_cost: Double?
        }
        let outer = try Outer(from: decoder)
        return .stats(
            inputTokens: outer.total_input_tokens ?? 0,
            outputTokens: outer.total_output_tokens ?? 0,
            cost: outer.total_cost ?? 0
        )
    }
}

// Helper for arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        default: try container.encode(String(describing: value))
        }
    }
}
