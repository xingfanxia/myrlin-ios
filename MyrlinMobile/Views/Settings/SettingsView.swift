import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var connectionTestResult: String? = nil
    @State private var showLogoutAlert: Bool = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    var body: some View {
        Form {
            Section("Server") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL").font(.caption).foregroundStyle(.secondary)
                    TextField("http://localhost:3456", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        if isTestingConnection { ProgressView() }
                    }
                }
                .disabled(isTestingConnection)

                if let result = connectionTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("\u{2713}") ? .green : .red)
                }

                NavigationLink("Usage & Cost") { CostView() }
                NavigationLink("Tunnels") { TunnelView() }
                NavigationLink("Discover Sessions") { DiscoverView() }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Account") {
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { serverURL = appState.serverURL }
        .alert("Logout?", isPresented: $showLogoutAlert) {
            Button("Logout", role: .destructive) { appState.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to log in again to connect to the server.")
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        connectionTestResult = nil
        defer { isTestingConnection = false }

        guard let url = URL(string: "\(serverURL)/api/auth/check") else {
            connectionTestResult = "\u{2717} Invalid URL"
            return
        }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            if let token = AuthService.shared.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                connectionTestResult = "\u{2713} Connected"
            } else {
                connectionTestResult = "\u{2717} Server error"
            }
        } catch {
            connectionTestResult = "\u{2717} \(error.localizedDescription)"
        }
    }
}
