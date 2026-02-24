import SwiftUI

/// Root view: gates on authentication state, shows MainView or LoginView.
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isAuthenticated {
            MainView()
        } else {
            LoginView()
        }
    }
}

/// Main navigation root: iPad gets NavigationSplitView, iPhone gets NavigationStack.
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedWorkspace: Workspace? = nil
    @State private var selectedSession: Session? = nil

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            SidebarView(selectedWorkspace: $selectedWorkspace)
        } content: {
            if let workspace = selectedWorkspace {
                SessionListView(workspace: workspace, selectedSession: $selectedSession)
            } else {
                ContentUnavailableView("Select a workspace", systemImage: "folder")
            }
        } detail: {
            if let session = selectedSession {
                MobileSessionView(session: session)
            } else {
                ContentUnavailableView("Select a session", systemImage: "terminal")
            }
        }
        // Clear selection when the selected session is deleted (iPad)
        .onChange(of: appState.sessions) { sessions in
            if let sel = selectedSession, !sessions.contains(where: { $0.id == sel.id }) {
                selectedSession = nil
            }
        }
    }

    private var iPhoneLayout: some View {
        NavigationStack {
            SidebarView(selectedWorkspace: $selectedWorkspace)
                .navigationDestination(for: Workspace.self) { workspace in
                    SessionListView(workspace: workspace, selectedSession: $selectedSession)
                }
                .navigationDestination(for: Session.self) { session in
                    MobileSessionView(session: session)
                }
        }
    }
}
