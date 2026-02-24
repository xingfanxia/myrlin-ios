import SwiftUI

struct SessionListView: View {
    let workspace: Workspace
    @Binding var selectedSession: Session?
    @EnvironmentObject var appState: AppState
    @State private var showNewSession = false
    @State private var newSessionName = ""
    @State private var newSessionModel = "claude-opus-4-5"
    @State private var newSessionWorkingDir = ""
    @State private var newSessionBypassPerms = false
    @State private var newSessionVerbose = false
    @State private var newSessionAgentTeams = false
    @State private var newSessionCreateWorktree = false
    @State private var newSessionBranch = ""
    @State private var newSessionBaseBranch = "main"
    @State private var showSearch = false
    @State private var sessionToRename: Session? = nil
    @State private var renameText = ""
    @State private var error: String? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var sessions: [Session] {
        appState.sessions.filter { $0.workspaceId == workspace.id }
    }

    var body: some View {
        if sizeClass == .regular {
            ipadList
        } else {
            iphoneList
        }
    }

    private var ipadList: some View {
        List(selection: $selectedSession) {
            rowContent
        }
        .navigationTitle(workspace.name)
        .sessionToolbar(onAdd: { showNewSession = true }, onRefresh: { Task { await appState.refreshSessions(workspaceId: workspace.id) } }, onSearch: { showSearch = true })
        .task { await appState.refreshSessions(workspaceId: workspace.id) }
        .refreshable { await appState.refreshSessions(workspaceId: workspace.id) }
        .overlay { emptyOverlay }
        .overlayError(error)
        .newSessionSheet(isPresented: $showNewSession, name: $newSessionName,
                         model: $newSessionModel, workingDir: $newSessionWorkingDir,
                         bypassPerms: $newSessionBypassPerms, verbose: $newSessionVerbose,
                         agentTeams: $newSessionAgentTeams,
                         createWorktree: $newSessionCreateWorktree,
                         branch: $newSessionBranch, baseBranch: $newSessionBaseBranch,
                         onCreate: createSession)
        .renameSessionAlert(item: $sessionToRename, text: $renameText, onRename: renameSession)
        .sheet(isPresented: $showSearch) { SearchView(workspaceId: workspace.id) }
    }

    private var iphoneList: some View {
        List {
            rowContent
        }
        .navigationTitle(workspace.name)
        .sessionToolbar(onAdd: { showNewSession = true }, onRefresh: { Task { await appState.refreshSessions(workspaceId: workspace.id) } }, onSearch: { showSearch = true })
        .task { await appState.refreshSessions(workspaceId: workspace.id) }
        .refreshable { await appState.refreshSessions(workspaceId: workspace.id) }
        .overlay { emptyOverlay }
        .overlayError(error)
        .newSessionSheet(isPresented: $showNewSession, name: $newSessionName,
                         model: $newSessionModel, workingDir: $newSessionWorkingDir,
                         bypassPerms: $newSessionBypassPerms, verbose: $newSessionVerbose,
                         agentTeams: $newSessionAgentTeams,
                         createWorktree: $newSessionCreateWorktree,
                         branch: $newSessionBranch, baseBranch: $newSessionBaseBranch,
                         onCreate: createSession)
        .renameSessionAlert(item: $sessionToRename, text: $renameText, onRename: renameSession)
        .sheet(isPresented: $showSearch) { SearchView(workspaceId: workspace.id) }
    }

    @ViewBuilder
    private var rowContent: some View {
        ForEach(sessions) { session in
            NavigationLink(value: session) {
                SessionRow(session: session)
            }
            .tag(session)
            .contextMenu {
                Button {
                    sessionToRename = session
                    renameText = session.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    Task { await restartSession(session) }
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await deleteSession(session) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await deleteSession(session) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    sessionToRename = session
                    renameText = session.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if sessions.isEmpty {
            ContentUnavailableView("No Sessions",
                systemImage: "terminal",
                description: Text("Tap + to create a session in this workspace."))
        }
    }

    // MARK: - Actions

    private func createSession() async {
        let name = newSessionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let dir = newSessionWorkingDir.trimmingCharacters(in: .whitespaces)
        do {
            if newSessionCreateWorktree {
                let branch = newSessionBranch.trimmingCharacters(in: .whitespaces)
                guard !branch.isEmpty, !dir.isEmpty else {
                    self.error = "Repo directory and branch name are required for worktree sessions"
                    return
                }
                // Server creates the git worktree + session atomically.
                // The resulting session arrives via SSE session:created → AppState auto-appends it.
                try await MyrlinAPI.shared.createWorktreeTask(
                    workspaceId: workspace.id,
                    repoDir: dir,
                    branch: branch,
                    description: name,
                    baseBranch: newSessionBaseBranch.isEmpty ? "main" : newSessionBaseBranch,
                    model: newSessionModel
                )
            } else {
                let dirArg = dir.isEmpty ? nil : dir
                let session = try await MyrlinAPI.shared.createSession(
                    name: name,
                    workspaceId: workspace.id,
                    workingDir: dirArg,
                    model: newSessionModel,
                    bypassPermissions: newSessionBypassPerms ? true : nil,
                    verbose: newSessionVerbose ? true : nil,
                    agentTeams: newSessionAgentTeams ? true : nil
                )
                try? await MyrlinAPI.shared.startSession(session.id)
                appState.sessions.append(session)
            }
        } catch {
            self.error = error.localizedDescription
        }
        newSessionName = ""
        newSessionWorkingDir = ""
        newSessionBypassPerms = false
        newSessionVerbose = false
        newSessionAgentTeams = false
        newSessionCreateWorktree = false
        newSessionBranch = ""
        newSessionBaseBranch = "main"
    }

    private func deleteSession(_ session: Session) async {
        do {
            try await MyrlinAPI.shared.deleteSession(session.id)
            appState.sessions.removeAll { $0.id == session.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func restartSession(_ session: Session) async {
        do {
            try await MyrlinAPI.shared.restartSession(session.id)
            await appState.refreshSessions(workspaceId: workspace.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func renameSession(session: Session, newName: String) async {
        do {
            let updated = try await MyrlinAPI.shared.updateSession(session.id, name: newName)
            if let idx = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                appState.sessions[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View Modifiers

private extension View {
    func sessionToolbar(onAdd: @escaping () -> Void, onRefresh: @escaping () -> Void, onSearch: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: onSearch) { Image(systemName: "magnifyingglass") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onAdd) { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }
            }
        }
    }

    func overlayError(_ error: String?) -> some View {
        self.overlay(alignment: .top) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.top, 8)
            }
        }
    }

    func newSessionSheet(isPresented: Binding<Bool>, name: Binding<String>,
                         model: Binding<String>, workingDir: Binding<String>,
                         bypassPerms: Binding<Bool>, verbose: Binding<Bool>,
                         agentTeams: Binding<Bool>,
                         createWorktree: Binding<Bool>,
                         branch: Binding<String>, baseBranch: Binding<String>,
                         onCreate: @escaping () async -> Void) -> some View {
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                Form {
                    Section("Session Name") {
                        TextField("My Session", text: name)
                            .autocorrectionDisabled()
                    }
                    Section("Model") {
                        Picker("Model", selection: model) {
                            Text("Opus 4.5 (recommended)").tag("claude-opus-4-5")
                            Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                            Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                        }
                    }

                    Section {
                        Toggle("Create in New Worktree", isOn: createWorktree)
                        if createWorktree.wrappedValue {
                            TextField("/path/to/repo (required)", text: workingDir)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                                .font(.callout.monospaced())
                            TextField("Branch name (e.g. feat/my-feature)", text: branch)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                                .font(.callout.monospaced())
                            TextField("Base branch (default: main)", text: baseBranch)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                                .font(.callout.monospaced())
                        } else {
                            TextField("/path/to/project (optional)", text: workingDir)
                                .autocorrectionDisabled()
                                .autocapitalization(.none)
                                .font(.callout.monospaced())
                        }
                    } header: {
                        Text(createWorktree.wrappedValue ? "Worktree" : "Working Directory")
                    } footer: {
                        if createWorktree.wrappedValue {
                            Text("Creates a new git worktree at the branch and opens a session inside it.")
                                .font(.caption)
                        }
                    }

                    if !createWorktree.wrappedValue {
                        Section("Flags") {
                            Toggle("Bypass Permissions", isOn: bypassPerms)
                            Toggle("Verbose Output", isOn: verbose)
                            Toggle("Agent Teams", isOn: agentTeams)
                        }
                    }
                }
                .navigationTitle("New Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented.wrappedValue = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            isPresented.wrappedValue = false
                            Task { await onCreate() }
                        }
                        .disabled(name.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .animation(.default, value: createWorktree.wrappedValue)
            }
            .presentationDetents([.large])
        }
    }

    func renameSessionAlert(item: Binding<Session?>, text: Binding<String>, onRename: @escaping (Session, String) async -> Void) -> some View {
        self.alert("Rename Session", isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            TextField("New name", text: text)
            Button("Rename") {
                if let session = item.wrappedValue {
                    let newName = text.wrappedValue
                    item.wrappedValue = nil
                    Task { await onRename(session, newName) }
                }
            }
            Button("Cancel", role: .cancel) { item.wrappedValue = nil }
        }
    }
}
