import Foundation

/// Represents a single renderable unit from the claude stream-json output.
/// One API event (a line of JSONL) can produce MULTIPLE StreamMessages via parseAll().
struct StreamMessage: Identifiable {
    let id: UUID = UUID()
    let type: MessageType
    let timestamp: Date = Date()

    enum MessageType {
        // Content blocks from assistant messages
        case assistantText(content: String)
        case thinking(content: String)
        case toolUse(name: String, toolUseId: String, inputJSON: String)

        // Tool results from user messages
        case toolResult(content: String, toolUseId: String?, isError: Bool)

        // User-originated
        case userMessage(content: String)

        // System events
        case systemInit(model: String, tools: [String], cwd: String?)
        case systemMessage(content: String, subtype: String)

        // Turn result / stats
        case stats(inputTokens: Int, outputTokens: Int, cost: Double)
    }
}

// MARK: - Local user message injection

extension StreamMessage {
    init(localUserMessage text: String) {
        self.type = .userMessage(content: text)
    }
}

// MARK: - Multi-message parser (one JSONL line → [StreamMessage])

extension StreamMessage {
    /// Parse a single JSONL line into zero or more StreamMessages.
    /// One assistant event with N content blocks → N StreamMessages.
    static func parseAll(from data: Data) -> [StreamMessage] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = obj["type"] as? String else { return [] }

        switch eventType {

        case "assistant":
            return parseAssistantEvent(obj)

        case "user", "human":
            return parseUserEvent(obj)

        case "result":
            return parseResultEvent(obj).map { [$0] } ?? []

        case "system":
            return parseSystemEvent(obj).map { [$0] } ?? []

        default:
            return []
        }
    }

    // MARK: - Assistant event → content blocks

    private static func parseAssistantEvent(_ obj: [String: Any]) -> [StreamMessage] {
        guard let message = obj["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            // Flat format fallback: {type:"assistant", content:"..."}
            if let text = obj["content"] as? String, !text.isEmpty {
                return [StreamMessage(type: .assistantText(content: text))]
            }
            return []
        }

        var results: [StreamMessage] = []
        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    results.append(StreamMessage(type: .assistantText(content: text)))
                }

            case "thinking":
                // Thinking blocks use field "thinking", not "text"
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    results.append(StreamMessage(type: .thinking(content: thinking)))
                }

            case "tool_use":
                let name = block["name"] as? String ?? "unknown_tool"
                let toolUseId = block["id"] as? String ?? ""
                let inputJSON: String
                if let input = block["input"],
                   let inputData = try? JSONSerialization.data(withJSONObject: input, options: .prettyPrinted),
                   let str = String(data: inputData, encoding: .utf8) {
                    inputJSON = str
                } else {
                    inputJSON = "{}"
                }
                results.append(StreamMessage(type: .toolUse(name: name, toolUseId: toolUseId, inputJSON: inputJSON)))

            default:
                break
            }
        }
        return results
    }

    // MARK: - User event → tool results

    private static func parseUserEvent(_ obj: [String: Any]) -> [StreamMessage] {
        guard let message = obj["message"] as? [String: Any],
              let contentBlocks = message["content"] as? [[String: Any]] else {
            // Flat user message (rare / local injection)
            if let text = obj["content"] as? String, !text.isEmpty {
                return [StreamMessage(type: .userMessage(content: text))]
            }
            return []
        }

        var results: [StreamMessage] = []
        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "tool_result":
                let toolUseId = block["tool_use_id"] as? String
                let isError = block["is_error"] as? Bool ?? false
                let content = extractToolResultContent(block["content"])
                if !content.isEmpty {
                    results.append(StreamMessage(type: .toolResult(
                        content: content, toolUseId: toolUseId, isError: isError)))
                }

            case "text":
                // Human text turn
                if let text = block["text"] as? String, !text.isEmpty {
                    results.append(StreamMessage(type: .userMessage(content: text)))
                }

            default:
                break
            }
        }
        return results
    }

    /// Tool result content can be a string, or an array of content blocks.
    private static func extractToolResultContent(_ raw: Any?) -> String {
        if let str = raw as? String { return str }
        if let blocks = raw as? [[String: Any]] {
            return blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        }
        return ""
    }

    // MARK: - Result / stats event

    private static func parseResultEvent(_ obj: [String: Any]) -> StreamMessage? {
        let cost = (obj["total_cost_usd"] as? Double) ?? (obj["cost_usd"] as? Double) ?? 0
        var inputTokens = 0
        var outputTokens = 0
        if let usage = obj["usage"] as? [String: Any] {
            inputTokens = usage["input_tokens"] as? Int ?? 0
            outputTokens = usage["output_tokens"] as? Int ?? 0
        }
        return StreamMessage(type: .stats(
            inputTokens: inputTokens, outputTokens: outputTokens, cost: cost))
    }

    // MARK: - System event

    private static func parseSystemEvent(_ obj: [String: Any]) -> StreamMessage? {
        let subtype = obj["subtype"] as? String ?? ""

        if subtype == "init" {
            let model = obj["model"] as? String ?? "unknown"
            let tools = obj["tools"] as? [String] ?? []
            let cwd = obj["cwd"] as? String
            return StreamMessage(type: .systemInit(model: model, tools: tools, cwd: cwd))
        }

        // turn_complete is handled by MobileSessionClient separately; skip rendering it
        if subtype == "turn_complete" { return nil }

        let content = obj["content"] as? String ?? obj["message"] as? String ?? ""
        if content.isEmpty && subtype.isEmpty { return nil }
        return StreamMessage(type: .systemMessage(content: content, subtype: subtype))
    }
}
