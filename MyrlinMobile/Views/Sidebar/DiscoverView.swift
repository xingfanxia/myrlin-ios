import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [DiscoveredProject] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var importing: Set<String> = []
    @State private var imported: Set<String> = []
    @State private var importErrors: [String: String] = [:]
    @State private var importedWorkspaceNames: [String: String] = [:]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Discovering sessions…")
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                }
                .padding()
            } else if projects.isEmpty {
                ContentUnavailableView("No Sessions Found",
                    systemImage: "magnifyingglass",
                    description: Text("No Claude Code sessions found in ~/.claude/projects/ on the server."))
            } else {
                List(projects) { project in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName(for: project))
                                .font(.callout)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Label("\(project.sessionCount)", systemImage: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let date = project.lastActive {
                                    Text(date.formatted(.relative(presentation: .named)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if project.hasClaudeMd == true {
                                    Image(systemName: "checkmark.seal")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                            if let err = importErrors[project.id] {
                                Text(err).font(.caption2).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if imported.contains(project.id) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                if let wsName = importedWorkspaceNames[project.id] {
                                    Text(wsName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        } else if importing.contains(project.id) {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Import") {
                                Task { await importProject(project) }
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
                .disabled(isLoading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            projects = try await MyrlinAPI.shared.discoverProjects()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func importProject(_ project: DiscoveredProject) async {
        importing.insert(project.id)
        importErrors.removeValue(forKey: project.id)
        defer { importing.remove(project.id) }
        do {
            let workspace = appState.workspaces.first
            let wsId = workspace?.id ?? ""
            let workingDir: String? = project.realPath.hasPrefix("/") ? project.realPath : nil
            let name: String = {
                if project.realPath.hasPrefix("/") {
                    return shortenPath(project.realPath)
                }
                let decoded = decodedEncodedName(project.encodedName)
                return decoded.isEmpty ? project.encodedName : decoded
            }()
            let created = try await MyrlinAPI.shared.createSession(
                name: name,
                workspaceId: wsId,
                workingDir: workingDir,
                resumeSessionId: project.latestSessionId
            )
            try? await MyrlinAPI.shared.startSession(created.id)
            var launched = created
            launched.status = .running
            // Ensure claudeSessionId is populated locally even if the server response
            // omitted it (older server versions). This guarantees --resume works when
            // MobileSessionView opens the WebSocket connection.
            if launched.claudeSessionId == nil, let resumeId = project.latestSessionId {
                launched.claudeSessionId = resumeId
            }
            appState.sessions.append(launched)
            imported.insert(project.id)
            importedWorkspaceNames[project.id] = workspace?.name ?? "first workspace"
        } catch {
            importErrors[project.id] = error.localizedDescription
        }
    }

    /// Returns the display name for a discovered project row.
    /// Uses `shortenPath` for real absolute paths; decodes `encodedName` otherwise.
    private func displayName(for project: DiscoveredProject) -> String {
        if project.realPath.hasPrefix("/") {
            return shortenPath(project.realPath)
        }
        let decoded = decodedEncodedName(project.encodedName)
        return decoded.isEmpty ? project.encodedName : decoded
    }

    /// Decodes a Claude-encoded project name (hyphen-separated tokens) into a
    /// human-readable label: splits by `-`, drops empty parts, takes the last 2
    /// non-empty tokens, and joins them with `-`.
    private func decodedEncodedName(_ encodedName: String) -> String {
        let tokens = encodedName.split(separator: "-").map(String.init).filter { !$0.isEmpty }
        let last2 = tokens.suffix(2)
        return last2.joined(separator: "-")
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return (path as NSString).lastPathComponent
    }
}
