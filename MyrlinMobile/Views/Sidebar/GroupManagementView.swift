import SwiftUI

/// Manage workspace groups: create, rename, delete, and move workspaces between groups.
struct GroupManagementView: View {
    @EnvironmentObject var appState: AppState
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var groupToRename: WorkspaceGroup? = nil
    @State private var renameText = ""
    @State private var error: String? = nil

    private var groups: [WorkspaceGroup] { appState.groups }

    private func workspacesInGroup(_ groupId: String) -> [Workspace] {
        appState.workspaces.filter { $0.groupId == groupId }
    }

    private var ungroupedWorkspaces: [Workspace] {
        appState.workspaces.filter { $0.groupId == nil }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            // Grouped workspaces
            ForEach(groups) { group in
                Section {
                    ForEach(workspacesInGroup(group.id)) { workspace in
                        HStack {
                            Circle()
                                .fill(Color(hex: workspace.color ?? "") ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(workspace.name)
                            Spacer()
                            Button {
                                Task { await removeFromGroup(workspace) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Add workspace to group menu
                    if !ungroupedWorkspaces.isEmpty {
                        Menu {
                            ForEach(ungroupedWorkspaces) { ws in
                                Button(ws.name) {
                                    Task { await addToGroup(workspace: ws, group: group) }
                                }
                            }
                        } label: {
                            Label("Add Workspace", systemImage: "plus")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Button {
                            groupToRename = group
                            renameText = group.name
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            Task { await deleteGroup(group) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }

            // Ungrouped
            if !ungroupedWorkspaces.isEmpty {
                Section("Ungrouped") {
                    ForEach(ungroupedWorkspaces) { workspace in
                        HStack {
                            Circle()
                                .fill(Color(hex: workspace.color ?? "") ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(workspace.name)
                            Spacer()
                            if !groups.isEmpty {
                                Menu {
                                    ForEach(groups) { group in
                                        Button("Move to \(group.name)") {
                                            Task { await addToGroup(workspace: workspace, group: group) }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNewGroup = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewGroup) {
            NavigationStack {
                Form {
                    Section("Group Name") {
                        TextField("Client Work", text: $newGroupName)
                            .autocorrectionDisabled()
                    }
                }
                .navigationTitle("New Group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewGroup = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            showNewGroup = false
                            Task { await createGroup() }
                        }
                    }
                }
            }
            .presentationDetents([.height(200)])
        }
        .alert("Rename Group", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                if let group = groupToRename {
                    let name = renameText
                    groupToRename = nil
                    Task { await renameGroup(group, name: name) }
                }
            }
            Button("Cancel", role: .cancel) { groupToRename = nil }
        }
        .task { await appState.refreshWorkspaces() }
    }

    // MARK: - Actions

    private func createGroup() async {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let group = try await MyrlinAPI.shared.createGroup(name: name)
            appState.groups.append(group)
        } catch {
            self.error = error.localizedDescription
        }
        newGroupName = ""
    }

    private func deleteGroup(_ group: WorkspaceGroup) async {
        do {
            try await MyrlinAPI.shared.deleteGroup(group.id)
            appState.groups.removeAll { $0.id == group.id }
            for idx in appState.workspaces.indices where appState.workspaces[idx].groupId == group.id {
                appState.workspaces[idx].groupId = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func renameGroup(_ group: WorkspaceGroup, name: String) async {
        do {
            let updated = try await MyrlinAPI.shared.updateGroup(group.id, name: name)
            if let idx = appState.groups.firstIndex(where: { $0.id == group.id }) {
                appState.groups[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addToGroup(workspace: Workspace, group: WorkspaceGroup) async {
        do {
            try await MyrlinAPI.shared.addWorkspaceToGroup(workspaceId: workspace.id, groupId: group.id)
            if let idx = appState.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                appState.workspaces[idx].groupId = group.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func removeFromGroup(_ workspace: Workspace) async {
        // Move to "ungrouped" by sending empty groupId
        do {
            if let idx = appState.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                appState.workspaces[idx].groupId = nil
            }
            // Server call to remove from group (set groupId to null)
            _ = try await MyrlinAPI.shared.updateWorkspace(workspace.id)
        } catch {
            self.error = error.localizedDescription
            await appState.refreshWorkspaces()
        }
    }
}
