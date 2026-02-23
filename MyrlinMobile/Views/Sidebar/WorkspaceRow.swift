import SwiftUI

struct WorkspaceRow: View {
    let workspace: Workspace

    private var accentColor: Color {
        guard let hex = workspace.color else { return .blue }
        return Color(hex: hex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name).font(.body)
                if let count = workspace.sessionCount {
                    Text("\(count) session\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension Color {
    /// Initialize from hex string (#RRGGBB or RRGGBB)
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6,
              let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
