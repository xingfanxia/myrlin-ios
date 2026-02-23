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
                .overlay {
                    if workspace.isActive == true {
                        Circle()
                            .stroke(accentColor.opacity(0.4), lineWidth: 3)
                            .frame(width: 16, height: 16)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(workspace.name).font(.body)
                    if workspace.isActive == true {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
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
