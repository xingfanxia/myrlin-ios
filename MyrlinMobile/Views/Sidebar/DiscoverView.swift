import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [DiscoveredSession] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var importing: Set<String> = []
    @State private var imported: Set<String> = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Discovering sessions…")
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else if sessions.isEmpty {
                ContentUnavailableView("No Sessions Found",
                    systemImage: "magnifyingglass",
                    description: Text("No existing Claude sessions were detected on the server."))
            } else {
                List(sessions) { session in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shortenPath(session.projectPath))
                                .font(.callout)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if let count = session.messageCount {
                                    Text("\(count) messages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let date = session.lastUsed {
                                    Text(date.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if imported.contains(session.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if importing.contains(session.id) {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Import") {
                                Task { await importSession(session) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Discover Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            sessions = try await MyrlinAPI.shared.discoverSessions()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func importSession(_ session: DiscoveredSession) async {
        importing.insert(session.id)
        defer { importing.remove(session.id) }
        do {
            let wsId = appState.workspaces.first?.id ?? ""
            let created = try await MyrlinAPI.shared.createSession(
                name: shortenPath(session.projectPath),
                workspaceId: wsId,
                workingDir: session.projectPath
            )
            appState.sessions.append(created)
            imported.insert(session.id)
        } catch {
            // Import failed — just remove from importing set
        }
    }

    private func shortenPath(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
