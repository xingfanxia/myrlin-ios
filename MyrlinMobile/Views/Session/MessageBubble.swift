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

// MARK: - Markdown Renderer (block + inline)

/// Full block-level markdown renderer.
/// Handles: headings (H1–H3), unordered/ordered lists, blockquotes,
/// fenced code blocks, horizontal rules, and inline formatting
/// (bold, italic, inline-code, links via AttributedString).
struct MarkdownWithCodeBlocks: View {
    let text: String
    var bodyFont: Font = .body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    // MARK: - Block model

    private enum MdBlock {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case codeBlock(lang: String, text: String)
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case blockquote(text: String)
        case horizontalRule
    }

    // MARK: - Block renderer

    @ViewBuilder
    private func blockView(_ block: MdBlock) -> some View {
        switch block {

        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 4 : 2)

        case .paragraph(let text):
            inlineText(text)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let lang, let code):
            CodeBlockView(lang: lang, code: code, codeFont: codeFont)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(bodyFont)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 12, alignment: .center)
                        inlineText(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(bodyFont)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 20, alignment: .trailing)
                        inlineText(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                inlineText(text)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 2)
        }
    }

    // MARK: - Inline text (bold / italic / code / links via AttributedString)

    @ViewBuilder
    private func inlineText(_ raw: String) -> some View {
        Text(styledAttributed(raw))
            .font(bodyFont)
            .textSelection(.enabled)
    }

    /// Parse inline markdown and tint code runs orange.
    /// Separated from the @ViewBuilder context so `for` loops are allowed.
    private func styledAttributed(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attributed = try? AttributedString(markdown: raw, options: opts) else {
            return AttributedString(raw)
        }
        // Collect ranges first to avoid mutating during iteration
        let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRanges {
            attributed[range].foregroundColor = Color.orange
        }
        return attributed
    }

    // MARK: - Fonts

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }

    private var codeFont: Font {
        switch bodyFont {
        case .callout: return .caption2.monospaced()
        case .title3:  return .callout.monospaced()
        default:       return .caption.monospaced()
        }
    }

    // MARK: - Block parser

    private var parsedBlocks: [MdBlock] { parseBlocks(text) }

    private func parseBlocks(_ input: String) -> [MdBlock] {
        var result: [MdBlock] = []
        let lines = input.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if t.isEmpty { i += 1; continue }

            // Fenced code block
            if t.hasPrefix("```") {
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let cl = lines[i].trimmingCharacters(in: .whitespaces)
                    if cl.hasPrefix("```") { i += 1; break }
                    codeLines.append(lines[i])
                    i += 1
                }
                result.append(.codeBlock(lang: lang, text: codeLines.joined(separator: "\n")))
                continue
            }

            // Headings
            if t.hasPrefix("### ") { result.append(.heading(level: 3, text: String(t.dropFirst(4)))); i += 1; continue }
            if t.hasPrefix("## ")  { result.append(.heading(level: 2, text: String(t.dropFirst(3)))); i += 1; continue }
            if t.hasPrefix("# ")   { result.append(.heading(level: 1, text: String(t.dropFirst(2)))); i += 1; continue }

            // Horizontal rule (--- *** ___ with optional spaces)
            let hrCheck = t.replacingOccurrences(of: " ", with: "")
            if hrCheck == "---" || hrCheck == "***" || hrCheck == "___" {
                result.append(.horizontalRule); i += 1; continue
            }

            // Unordered list
            if isULItem(t) {
                var items: [String] = []
                while i < lines.count && isULItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(ulText(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                result.append(.unorderedList(items: items))
                continue
            }

            // Ordered list
            if isOLItem(t) {
                var items: [String] = []
                while i < lines.count && isOLItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(olText(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                result.append(.orderedList(items: items))
                continue
            }

            // Blockquote
            if t.hasPrefix(">") {
                var qLines: [String] = []
                while i < lines.count {
                    let qt = lines[i].trimmingCharacters(in: .whitespaces)
                    if !qt.hasPrefix(">") { break }
                    qLines.append(qt.hasPrefix("> ") ? String(qt.dropFirst(2)) : String(qt.dropFirst(1)))
                    i += 1
                }
                result.append(.blockquote(text: qLines.joined(separator: "\n")))
                continue
            }

            // Paragraph — accumulate until blank line or block-level marker
            var pLines: [String] = []
            while i < lines.count {
                let pt = lines[i].trimmingCharacters(in: .whitespaces)
                if pt.isEmpty { i += 1; break }
                let hrp = pt.replacingOccurrences(of: " ", with: "")
                if pt.hasPrefix("```") || pt.hasPrefix("# ") || pt.hasPrefix("## ") ||
                   pt.hasPrefix("### ") || isULItem(pt) || isOLItem(pt) || pt.hasPrefix(">") ||
                   hrp == "---" || hrp == "***" || hrp == "___" { break }
                pLines.append(lines[i])
                i += 1
            }
            if !pLines.isEmpty {
                result.append(.paragraph(text: pLines.joined(separator: "\n")))
            }
        }
        return result
    }

    // MARK: - List helpers

    private func isULItem(_ t: String) -> Bool {
        t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }
    private func isOLItem(_ t: String) -> Bool {
        t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }
    private func ulText(_ t: String) -> String {
        (t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")) ? String(t.dropFirst(2)) : t
    }
    private func olText(_ t: String) -> String {
        guard let r = t.range(of: #"^\d+\.\s"#, options: .regularExpression) else { return t }
        return String(t[r.upperBound...])
    }
}

// MARK: - Syntax-highlighted code block

private struct CodeBlockView: View {
    let lang: String
    let code: String
    let codeFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: language pill + copy button
            HStack(spacing: 8) {
                if !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray4).opacity(0.6))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.systemGray5))

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(codeLines.enumerated()), id: \.offset) { _, line in
                        highlightedLine(line)
                            .font(codeFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var codeLines: [String] {
        code.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
    }

    // Build a single `Text` from syntax tokens (concatenation preserves per-run color).
    private func highlightedLine(_ line: String) -> Text {
        Self.tokenize(line).reduce(Text("")) { acc, tok in
            acc + Text(tok.text).foregroundColor(tok.color)
        }
    }

    // MARK: - Token model

    private struct SyntaxToken {
        let text: String
        let color: Color
    }

    // MARK: - Tokenizer

    private static func tokenize(_ line: String) -> [SyntaxToken] {
        guard !line.isEmpty else { return [] }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Whole-line comment
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("--") ||
           trimmed.hasPrefix("# ") || trimmed == "#" {
            return [SyntaxToken(text: line, color: commentColor)]
        }

        var tokens: [SyntaxToken] = []
        var chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // Inline // comment — rest of line
            if ch == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                tokens.append(SyntaxToken(text: String(chars[i...]), color: commentColor))
                break
            }

            // String literal " or '
            if ch == "\"" || ch == "'" {
                var str = String(ch)
                i += 1
                while i < chars.count {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        str.append(chars[i]); str.append(chars[i + 1]); i += 2
                    } else if chars[i] == ch {
                        str.append(chars[i]); i += 1; break
                    } else {
                        str.append(chars[i]); i += 1
                    }
                }
                tokens.append(SyntaxToken(text: str, color: stringColor))
                continue
            }

            // Number (int or float, including hex 0x...)
            if ch.isNumber || (ch == "0" && i + 1 < chars.count && chars[i + 1] == "x") {
                var num = String(ch); i += 1
                while i < chars.count && (chars[i].isHexDigit || chars[i] == "." || chars[i] == "_") {
                    num.append(chars[i]); i += 1
                }
                tokens.append(SyntaxToken(text: num, color: numberColor))
                continue
            }

            // Word (identifier or keyword)
            if ch.isLetter || ch == "_" {
                var word = String(ch); i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i]); i += 1
                }
                let color = keywords.contains(word) ? keywordColor : Color(UIColor.label)
                tokens.append(SyntaxToken(text: word, color: color))
                continue
            }

            // Everything else (operators, punctuation, whitespace)
            tokens.append(SyntaxToken(text: String(ch), color: Color(UIColor.label)))
            i += 1
        }

        return tokens
    }

    // MARK: - Colors (system colors adapt to dark / light mode)

    private static let keywordColor = Color(UIColor.systemBlue)
    private static let stringColor  = Color(UIColor.systemOrange)
    private static let commentColor = Color(UIColor.systemGreen).opacity(0.85)
    private static let numberColor  = Color(UIColor.systemPurple)

    // MARK: - Keyword set (Swift, Python, JS/TS, Go, Rust, SQL, Shell)

    private static let keywords: Set<String> = [
        // Swift
        "var", "let", "func", "class", "struct", "enum", "protocol", "extension",
        "import", "return", "if", "else", "guard", "for", "while", "do", "switch",
        "case", "break", "continue", "defer", "in", "is", "as", "try", "catch",
        "throw", "throws", "rethrows", "async", "await", "actor", "self", "super",
        "init", "deinit", "subscript", "static", "final", "override", "mutating",
        "lazy", "weak", "unowned", "inout", "typealias", "associatedtype",
        "open", "public", "internal", "private", "fileprivate",
        "nil", "true", "false", "where", "some", "any", "opaque",
        // Python
        "def", "pass", "with", "from", "lambda", "yield", "raise", "except",
        "finally", "not", "and", "or", "None", "True", "False", "print",
        "range", "len", "self", "cls", "global", "nonlocal", "del", "assert",
        // JS / TS
        "const", "function", "typeof", "instanceof", "new", "delete", "void",
        "undefined", "null", "this", "export", "default", "interface", "type",
        "namespace", "abstract", "implements", "extends", "declare", "readonly",
        "keyof", "typeof", "satisfies", "override",
        // Go
        "package", "go", "chan", "select", "map", "make", "append", "range",
        "goroutine", "defer", "fallthrough",
        // Rust
        "fn", "use", "mod", "pub", "impl", "trait", "where", "match", "ref",
        "mut", "move", "unsafe", "extern", "crate", "super", "self", "loop",
        // SQL
        "SELECT", "FROM", "WHERE", "JOIN", "ON", "GROUP", "BY", "ORDER",
        "HAVING", "INSERT", "INTO", "UPDATE", "SET", "DELETE", "CREATE",
        "TABLE", "INDEX", "DROP", "ALTER", "ADD", "COLUMN", "PRIMARY", "KEY",
        // Shell / Bash
        "echo", "export", "source", "alias", "unset", "readonly",
        // Common primitives
        "int", "string", "bool", "float", "double", "char", "byte",
        "void", "object", "array", "number", "boolean",
    ]
}
