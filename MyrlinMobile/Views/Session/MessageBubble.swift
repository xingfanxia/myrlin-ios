import SwiftUI

/// Renders a single StreamMessage with appropriate styling per type.
struct MessageBubble: View {
    let message: StreamMessage
    @State private var isExpanded: Bool = false

    var body: some View {
        switch message.type {
        case .assistantText(let content):
            assistantBubble(content: content)

        case .userMessage(let content):
            userBubble(content: content)

        case .thinking(let content):
            thinkingCard(content: content)

        case .toolUse(let name, let input):
            toolCard(name: name, input: input)

        case .toolResult(let content, _):
            toolResultCard(content: content)

        case .systemMessage(let content, let subtype):
            systemLabel(content: content, subtype: subtype)

        case .stats:
            EmptyView()  // Stats handled by StatsBar

        case .raw:
            EmptyView()
        }
    }

    // MARK: - Bubble Styles

    private func assistantBubble(content: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .cornerRadius(12)
            Spacer(minLength: 40)
        }
    }

    private func userBubble(content: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.blue)
                .cornerRadius(12)
        }
    }

    private func thinkingCard(content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                    Text("Thinking...")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .bottom], 10)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func toolCard(name: String, input: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: toolIcon(for: name))
                        .foregroundStyle(.orange)
                    Text(name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(prettyPrint(input))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func toolResultCard(content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("Tool Result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                Text(content)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .lineLimit(20)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func systemLabel(content: String, subtype: String) -> some View {
        HStack {
            Spacer()
            Text(content)
                .font(.caption)
                .foregroundStyle(subtype == "stderr" ? .red : .secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func toolIcon(for name: String) -> String {
        switch name.lowercased() {
        case _ where name.lowercased().contains("bash"): return "terminal"
        case _ where name.lowercased().contains("file"), _ where name.lowercased().contains("read"): return "doc.text"
        case _ where name.lowercased().contains("write"): return "pencil"
        case _ where name.lowercased().contains("search"): return "magnifyingglass"
        case _ where name.lowercased().contains("web"): return "globe"
        default: return "wrench"
        }
    }

    private func prettyPrint(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return json
        }
        return str
    }
}
