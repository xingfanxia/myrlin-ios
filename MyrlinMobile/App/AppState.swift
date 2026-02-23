import Foundation
import Combine

/// Central application state: auth credentials, server URL, and connection status.
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var serverURL: String = ""
    @Published var isConnecting: Bool = false
    @Published var connectionError: String? = nil

    private let authService = AuthService.shared

    init() {
        // Restore auth state from Keychain on launch
        if let savedURL = authService.serverURL, let _ = authService.token {
            serverURL = savedURL
            isAuthenticated = true
        }
    }

    func login(serverURL: String, password: String) async {
        isConnecting = true
        connectionError = nil
        do {
            try await authService.login(serverURL: serverURL, password: password)
            self.serverURL = serverURL
            isAuthenticated = true
        } catch {
            connectionError = error.localizedDescription
        }
        isConnecting = false
    }

    func logout() {
        authService.logout()
        isAuthenticated = false
        serverURL = ""
    }
}
