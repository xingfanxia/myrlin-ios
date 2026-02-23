import SwiftUI

/// Sidebar: displays workspaces list. Used in iPad split view and iPhone navigation root.
struct SidebarView: View {
    @Binding var selectedWorkspace: Workspace?
    @EnvironmentObject var appState: AppState
    @State private var showNewWorkspace = false
    @State private var newWorkspaceName = ""
    @State private var workspaceToRename: Workspace? = nil
    @State private var renameText = ""
    @State private var workspaceForDocs: Workspace? = nil
    @State private var showDiscover = false
    @State private var error: String? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var workspaces: [Workspace] { appState.workspaces }

    var body: some View {
        if sizeClass == .regular {
            ipadList
        } else {
            iphoneList
        }
    }

    // MARK: - iPad list

    private var ipadList: some View {
        List(selection: $selectedWorkspace) {
            rowContent
        }
        .navigationTitle("Workspaces")
        .sharedToolbar(onAdd: { showNewWorkspace = true }, onRefresh: { Task { await appState.refreshWorkspaces() } }, onDiscover: { showDiscover = true })
        .task { if !appState.workspacesLoaded { await appState.refreshWorkspaces() } }
        .refreshable { await appState.refreshWorkspaces() }
        .overlayError(error)
        .newWorkspaceSheet(isPresented: $showNewWorkspace, name: $newWorkspaceName, onCreate: createWorkspace)
        .renameAlert(item: $workspaceToRename, text: $renameText, onRename: renameWorkspace)
        .sheet(item: $workspaceForDocs) { ws in
            NavigationStack { WorkspaceDocsView(workspace: ws) }
        }
        .sheet(isPresented: $showDiscover) { NavigationStack { DiscoverView() } }
    }

    // MARK: - iPhone list

    private var iphoneList: some View {
        List {
            rowContent
        }
        .navigationTitle("Workspaces")
        .sharedToolbar(onAdd: { showNewWorkspace = true }, onRefresh: { Task { await appState.refreshWorkspaces() } }, onDiscover: { showDiscover = true })
        .task { if !appState.workspacesLoaded { await appState.refreshWorkspaces() } }
        .refreshable { await appState.refreshWorkspaces() }
        .overlayError(error)
        .newWorkspaceSheet(isPresented: $showNewWorkspace, name: $newWorkspaceName, onCreate: createWorkspace)
        .renameAlert(item: $workspaceToRename, text: $renameText, onRename: renameWorkspace)
        .sheet(item: $workspaceForDocs) { ws in
            NavigationStack { WorkspaceDocsView(workspace: ws) }
        }
        .sheet(isPresented: $showDiscover) { NavigationStack { DiscoverView() } }
    }

    // MARK: - Shared row content

    @ViewBuilder
    private var rowContent: some View {
        if !appState.workspacesLoaded {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if workspaces.isEmpty {
            Text("No workspaces")
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        } else {
            ForEach(workspaces) { workspace in
                NavigationLink(value: workspace) {
                    WorkspaceRow(workspace: workspace)
                }
                .tag(workspace)
                .contextMenu {
                    Button {
                        workspaceToRename = workspace
                        renameText = workspace.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        Task { await activateWorkspace(workspace) }
                    } label: {
                        Label("Activate", systemImage: "star")
                    }
                    Button {
                        workspaceForDocs = workspace
                    } label: {
                        Label("View Docs", systemImage: "doc.text")
                    }
                    Divider()
                    Button(role: .destructive) {
                        Task { await deleteWorkspace(workspace) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await deleteWorkspace(workspace) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { indices, destination in
                appState.workspaces.move(fromOffsets: indices, toOffset: destination)
                let ids = appState.workspaces.map(\.id)
                Task { try? await MyrlinAPI.shared.reorderWorkspaces(ids) }
            }
        }
    }

    // MARK: - Actions

    private func createWorkspace() async {
        guard !newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let ws = try await MyrlinAPI.shared.createWorkspace(name: newWorkspaceName)
            appState.workspaces.append(ws)
        } catch {
            self.error = error.localizedDescription
        }
        newWorkspaceName = ""
    }

    private func deleteWorkspace(_ workspace: Workspace) async {
        do {
            try await MyrlinAPI.shared.deleteWorkspace(workspace.id)
            appState.workspaces.removeAll { $0.id == workspace.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func activateWorkspace(_ workspace: Workspace) async {
        do {
            try await MyrlinAPI.shared.activateWorkspace(workspace.id)
            for idx in appState.workspaces.indices {
                appState.workspaces[idx].isActive = (appState.workspaces[idx].id == workspace.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func renameWorkspace(workspace: Workspace, newName: String) async {
        do {
            let updated = try await MyrlinAPI.shared.updateWorkspace(workspace.id, name: newName)
            if let idx = appState.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                appState.workspaces[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Shared toolbar modifier

private extension View {
    func sharedToolbar(onAdd: @escaping () -> Void, onRefresh: @escaping () -> Void, onDiscover: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: GroupManagementView()) {
                    Image(systemName: "folder")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: onDiscover) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
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

    func newWorkspaceSheet(isPresented: Binding<Bool>, name: Binding<String>, onCreate: @escaping () async -> Void) -> some View {
        self.sheet(isPresented: isPresented) {
            NavigationStack {
                Form {
                    Section("Workspace Name") {
                        TextField("My Workspace", text: name)
                            .autocorrectionDisabled()
                    }
                }
                .navigationTitle("New Workspace")
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
                    }
                }
            }
            .presentationDetents([.height(200)])
        }
    }

    func renameAlert(item: Binding<Workspace?>, text: Binding<String>, onRename: @escaping (Workspace, String) async -> Void) -> some View {
        self.alert("Rename Workspace", isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            TextField("New name", text: text)
            Button("Rename") {
                if let ws = item.wrappedValue {
                    let newName = text.wrappedValue
                    item.wrappedValue = nil
                    Task { await onRename(ws, newName) }
                }
            }
            Button("Cancel", role: .cancel) { item.wrappedValue = nil }
        }
    }
}
