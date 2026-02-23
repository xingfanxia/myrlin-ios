import SwiftUI

/// Sidebar: displays workspaces list. Used in iPad split view and iPhone navigation root.
struct SidebarView: View {
    @Binding var selectedWorkspace: Workspace?
    @State private var workspaces: [Workspace] = []
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        List(selection: $selectedWorkspace) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let error {
                VStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(workspaces) { workspace in
                    NavigationLink(value: workspace) {
                        WorkspaceRow(workspace: workspace)
                    }
                    .tag(workspace)
                }
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            workspaces = try await MyrlinAPI.shared.workspaces()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
