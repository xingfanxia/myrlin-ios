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
                            Text(shortenPath(project.realPath.isEmpty ? project.encodedName : project.realPath))
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
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if importing.contains(project.id) {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button("Import") {
                                Task { await importProject(project) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(project.dirExists == false)
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
            let wsId = appState.workspaces.first?.id ?? ""
            let name = shortenPath(project.realPath)
            let created = try await MyrlinAPI.shared.createSession(
                name: name,
                workspaceId: wsId,
                workingDir: project.realPath
            )
            try? await MyrlinAPI.shared.startSession(created.id)
            appState.sessions.append(created)
            imported.insert(project.id)
        } catch {
            importErrors[project.id] = error.localizedDescription
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        }
        return (path as NSString).lastPathComponent
    }
}
