import SwiftUI

/// Renders a single StreamMessage with appropriate styling per type.
struct MessageBubble: View {
    let message: StreamMessage
    @State private var isExpanded: Bool = false

    @AppStorage("chatFontSize")       private var chatFontSize: String = "medium"
    @AppStorage("showThinkingBlocks") private var showThinkingBlocks: Bool = true
    @AppStorage("showToolBlocks")     private var showToolBlocks: Bool = true

    /// Body font scaled by the user's font-size preference.
    var bodyFont: Font {
        switch chatFontSize {
        case "small": return .callout
        case "large": return .title3
        default:      return .body
        }
    }

    var body: some View {
        switch message.type {

        case .assistantText(let content) where !content.isEmpty:
            assistantBubble(content: content)
                .padding(.bottom, 16)

        case .userMessage(let content) where !content.isEmpty:
            userBubble(content: content)
                .padding(.bottom, 16)

        case .thinking(let content) where showThinkingBlocks:
            thinkingCard(content: content)
                .padding(.bottom, 6)

        case .toolUse(let name, let toolUseId, let inputJSON) where showToolBlocks:
            toolUseCard(name: name, toolUseId: toolUseId, inputJSON: inputJSON)
                .padding(.bottom, 4)

        case .toolResult(let content, _, let isError) where !content.isEmpty && showToolBlocks:
            toolResultCard(content: content, isError: isError)
                .padding(.bottom, 6)

        case .systemInit(let model, let tools, let cwd):
            systemInitCard(model: model, tools: tools, cwd: cwd)
                .padding(.bottom, 14)

        case .systemMessage(let content, let subtype) where !content.isEmpty:
            systemLabel(content: content, subtype: subtype)
                .padding(.bottom, 8)

        default:
            EmptyView()
        }
    }

    // MARK: - Assistant bubble

    private func assistantBubble(content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Sender label
            HStack(spacing: 5) {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("Claude")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    MarkdownWithCodeBlocks(text: content, bodyFont: bodyFont)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contextMenu {
                    Button { UIPasteboard.general.string = content } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                Spacer(minLength: 44)
            }
        }
    }

    // MARK: - User bubble

    private func userBubble(content: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Sender label
            Text("You")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 44)
                Text(content)
                    .font(bodyFont)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contextMenu {
                        Button { UIPasteboard.general.string = content } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }

    // MARK: - Thinking card

    private func thinkingCard(content: String) -> some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.purple.opacity(0.4))
                .frame(width: 3)
                .padding(.vertical, 2)
            CollapsibleCard(
                isExpanded: $isExpanded,
                icon: "brain",
                iconColor: .purple,
                title: "Thinking",
                titleStyle: .captionItalic
            ) {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding([.leading, .trailing, .bottom], 10)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 44)
        }
        .padding(.leading, 8)
    }

    // MARK: - Tool use card

    private func toolUseCard(name: String, toolUseId: String, inputJSON: String) -> some View {
        let isSubagent = name == "Task"
        let isAgentTeam = name == "Task" && inputJSON.contains("\"subagent_type\"")
        let accentColor: Color = isSubagent ? .indigo : .orange

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 2)
            CollapsibleCard(
                isExpanded: $isExpanded,
                icon: isSubagent ? (isAgentTeam ? "person.3.fill" : "person.fill.badge.plus") : toolIcon(for: name),
                iconColor: accentColor,
                title: isSubagent ? subagentTitle(from: inputJSON) : name,
                titleStyle: .captionMono,
                badge: isSubagent ? "subagent" : nil
            ) {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(inputJSON)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
            .background(isSubagent ? Color.indigo.opacity(0.08) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 44)
        }
        .padding(.leading, 8)
    }

    // MARK: - Tool result card

    private func toolResultCard(content: String, isError: Bool) -> some View {
        let isDiff = content.hasPrefix("diff --git") || content.contains("\n--- a/")
        let isManyLines = content.components(separatedBy: "\n").count > 8
        let accentColor: Color = isError ? .red : (isDiff ? .teal : .green)

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, 2)
            CollapsibleCard(
                isExpanded: $isExpanded,
                icon: isError ? "xmark.circle" : (isDiff ? "arrow.triangle.2.circlepath" : "checkmark.circle"),
                iconColor: accentColor,
                title: isError ? "Tool Error" : (isDiff ? "Diff" : "Tool Result"),
                titleStyle: .caption
            ) {
                Divider()
                if isDiff {
                    DiffView(text: content)
                        .padding(10)
                } else {
                    Text(content)
                        .font(.caption.monospaced())
                        .foregroundStyle(isError ? .red : .secondary)
                        .padding(10)
                        .lineLimit(isManyLines ? 30 : nil)
                }
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 44)
        }
        .padding(.leading, 8)
    }

    // MARK: - System init card

    private func systemInitCard(model: String, tools: [String], cwd: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let cwd {
                    Text((cwd as NSString).abbreviatingWithTildeInPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(tools.count) tools")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - System label

    private func systemLabel(content: String, subtype: String) -> some View {
        HStack {
            Spacer()
            Text(content)
                .font(.caption)
                .foregroundStyle(subtype == "stderr" ? Color.red : Color.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func toolIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("bash") || lower.contains("shell") { return "terminal" }
        if lower.contains("read") || lower.contains("file") { return "doc.text" }
        if lower.contains("write") || lower.contains("edit") { return "pencil" }
        if lower.contains("search") || lower.contains("grep") { return "magnifyingglass" }
        if lower.contains("web") || lower.contains("fetch") { return "globe" }
        if lower.contains("glob") { return "folder.badge.questionmark" }
        if lower.contains("notebook") { return "book" }
        return "wrench.and.screwdriver"
    }

    private func subagentTitle(from inputJSON: String) -> String {
        guard let data = inputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Task"
        }
        if let subagentType = obj["subagent_type"] as? String {
            return "Task · \(subagentType)"
        }
        if let description = obj["description"] as? String {
            return String(description.prefix(40))
        }
        return "Task"
    }
}

// MARK: - Collapsible card (shared shell)

private struct CollapsibleCard<Content: View>: View {
    @Binding var isExpanded: Bool
    let icon: String
    let iconColor: Color
    let title: String
    let titleStyle: TitleStyle
    var badge: String? = nil
    @ViewBuilder let content: () -> Content

    enum TitleStyle { case caption, captionMono, captionItalic }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(iconColor)
                    titleText
                    if let badge {
                        Text(badge)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(iconColor.opacity(0.15))
                            .foregroundStyle(iconColor)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded { content() }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch titleStyle {
        case .caption:
            Text(title).font(.caption).foregroundStyle(.secondary)
        case .captionMono:
            Text(title).font(.caption.monospaced()).foregroundStyle(.primary)
        case .captionItalic:
            Text(title).font(.caption.italic()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Diff Renderer

/// Colors +/- lines in diff output like a terminal.
struct DiffView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(line.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct DiffLine {
        let text: String
        let color: Color
    }

    private var lines: [DiffLine] {
        text.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return DiffLine(text: line, color: .green)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                return DiffLine(text: line, color: .red)
            } else if line.hasPrefix("@@") {
                return DiffLine(text: line, color: .blue)
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") {
                return DiffLine(text: line, color: .secondary)
            } else {
                return DiffLine(text: line, color: .primary)
            }
        }
    }
}

// MARK: - Markdown with Code Blocks

struct MarkdownWithCodeBlocks: View {
    let text: String
    var bodyFont: Font = .body

    private var codeFont: Font {
        switch bodyFont {
        case .callout: return .caption2.monospaced()
        case .title3:  return .callout.monospaced()
        default:       return .caption.monospaced()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if segment.isCode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(segment.text)
                            .font(codeFont)
                            .foregroundStyle(.primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                } else if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let attributed = try? AttributedString(markdown: segment.text) {
                        Text(attributed)
                            .font(bodyFont)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(segment.text)
                            .font(bodyFont)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private struct Segment { let text: String; let isCode: Bool }

    private var segments: [Segment] {
        var result: [Segment] = []
        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            if i % 2 == 0 {
                result.append(Segment(text: part, isCode: false))
            } else {
                var lines = part.components(separatedBy: "\n")
                if let first = lines.first {
                    let hint = first.trimmingCharacters(in: .whitespaces)
                    if !hint.isEmpty && hint.range(of: "^[a-zA-Z0-9+#._-]+$", options: .regularExpression) != nil {
                        lines = Array(lines.dropFirst())
                    }
                }
                result.append(Segment(text: lines.joined(separator: "\n"), isCode: true))
            }
        }
        return result
    }
}
