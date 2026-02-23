import SwiftUI

struct StatsBar: View {
    let stats: StreamMessage

    private var inputTokens: Int {
        if case .stats(let input, _, _) = stats.type { return input }
        return 0
    }
    private var outputTokens: Int {
        if case .stats(_, let output, _) = stats.type { return output }
        return 0
    }
    private var cost: Double {
        if case .stats(_, _, let c) = stats.type { return c }
        return 0
    }

    var body: some View {
        HStack(spacing: 16) {
            Label(formatTokens(inputTokens), systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(formatTokens(outputTokens), systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatCost(cost))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }

    private func formatCost(_ c: Double) -> String {
        if c < 0.001 { return "<$0.001" }
        return String(format: "$%.3f", c)
    }
}
