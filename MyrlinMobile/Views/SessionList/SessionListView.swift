import SwiftUI

struct SessionListView: View {
    let workspace: Workspace
    @Binding var selectedSession: Session?
    @State private var sessions: [Session] = []
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        List(selection: $selectedSession) {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                    .tag(session)
                }
            }
        }
        .navigationTitle(workspace.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay {
            if sessions.isEmpty && !isLoading {
                ContentUnavailableView("No Sessions",
                    systemImage: "terminal",
                    description: Text("No sessions in this workspace."))
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            sessions = try await MyrlinAPI.shared.sessions(workspaceId: workspace.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
