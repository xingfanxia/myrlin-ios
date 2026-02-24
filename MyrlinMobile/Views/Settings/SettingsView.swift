import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLogoutAlert: Bool = false
    @State private var showSwitchServer: Bool = false
    @AppStorage("appearanceMode")     private var appearanceMode: String = "system"
    @AppStorage("chatFontSize")       private var chatFontSize: String = "medium"
    @AppStorage("showThinkingBlocks") private var showThinkingBlocks: Bool = true
    @AppStorage("showToolBlocks")     private var showToolBlocks: Bool = true

    var body: some View {
        Form {
            Section("Server") {
                // Current server
                HStack {
                    Label {
                        Text(appState.serverURL.isEmpty ? "Not connected" : appState.serverURL)
                            .font(.callout)
                            .foregroundStyle(appState.serverURL.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Button("Switch") { showSwitchServer = true }
                        .font(.callout)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
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

            Section("Chat Display") {
                Picker("Font Size", selection: $chatFontSize) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
                Toggle("Show Thinking Blocks", isOn: $showThinkingBlocks)
                Toggle("Show Tool Calls", isOn: $showToolBlocks)
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
        .alert("Logout?", isPresented: $showLogoutAlert) {
            Button("Logout", role: .destructive) { appState.logout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to log in again to connect to the server.")
        }
        .sheet(isPresented: $showSwitchServer) {
            SwitchServerSheet()
                .environmentObject(appState)
        }
    }
}

// MARK: - Switch Server Sheet

private struct SwitchServerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL: String = ""
    @State private var password: String = ""
    @State private var savedURLs: [String] = []
    @FocusState private var focusField: Field?

    enum Field { case url, password }

    private var activeURL: String { serverURL.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Saved server cards
                if !savedURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved Servers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)

                        VStack(spacing: 8) {
                            ForEach(savedURLs, id: \.self) { url in
                                ServerCard(
                                    url: url,
                                    isSelected: serverURL == url,
                                    isCurrent: url == appState.serverURL,
                                    onSelect: {
                                        serverURL = url
                                        focusField = .password
                                    },
                                    onDelete: { deleteServer(url) }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    HStack {
                        Rectangle().frame(height: 0.5).foregroundStyle(Color(.separator))
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                        Rectangle().frame(height: 0.5).foregroundStyle(Color(.separator))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }

                // Manual URL + password
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(savedURLs.isEmpty ? "Server URL" : "New Server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("http://localhost:3456", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusField, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focusField = .password }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password").font(.caption).foregroundStyle(.secondary)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await connect() } }
                    }
                }
                .padding(.horizontal, 32)

                if let error = appState.connectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                Button {
                    Task { await connect() }
                } label: {
                    if appState.isConnecting {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Connect").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeURL.isEmpty || password.isEmpty || appState.isConnecting)
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Spacer()
            }
            .navigationTitle("Switch Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                savedURLs = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
                // Pre-select the current server
                if !appState.serverURL.isEmpty {
                    serverURL = appState.serverURL
                    focusField = .password
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func connect() async {
        await appState.login(serverURL: activeURL, password: password)
        if appState.connectionError == nil {
            saveServerURL(activeURL)
            dismiss()
        }
    }

    private func saveServerURL(_ url: String) {
        guard !url.isEmpty else { return }
        var saved = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
        saved.removeAll { $0 == url }
        saved.insert(url, at: 0)
        UserDefaults.standard.set(Array(saved.prefix(5)), forKey: "savedServerURLs")
    }

    private func deleteServer(_ url: String) {
        var saved = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
        saved.removeAll { $0 == url }
        UserDefaults.standard.set(saved, forKey: "savedServerURLs")
        savedURLs = saved
        if serverURL == url { serverURL = "" }
    }
}

// MARK: - Server Card (with "current" badge)

private struct ServerCard: View {
    let url: String
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    private var displayHost: String {
        url.replacingOccurrences(of: "http://", with: "")
           .replacingOccurrences(of: "https://", with: "")
    }
    private var isSecure: Bool { url.hasPrefix("https://") }
    private var isLocal: Bool {
        url.contains("localhost") || url.contains("127.0.0.1") || url.contains("192.168.")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemBackground))
                        .frame(width: 38, height: 38)
                    Image(systemName: isLocal ? "house.fill" : "cloud.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(displayHost)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isCurrent {
                            Text("current")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: isSecure ? "lock.fill" : "lock.open.fill")
                            .font(.caption2)
                            .foregroundStyle(isSecure ? .green : .orange)
                        Text(isSecure ? "HTTPS" : "HTTP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(isLocal ? "Local" : "Remote")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
