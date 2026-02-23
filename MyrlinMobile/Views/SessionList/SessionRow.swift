import SwiftUI

struct SessionRow: View {
    let session: Session

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        case .unknown: return .orange
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dir = session.workingDir {
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                        Text((dir as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
