import SwiftUI

struct InputBar: View {
    let isConnected: Bool
    let onSend: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .focused($isFocused)
                .disabled(!isConnected)
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
            .sensoryFeedback(.impact, trigger: text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .top)
    }

    private var canSend: Bool {
        isConnected && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isConnected else { return }
        onSend(trimmed)
        text = ""
    }
}
