import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL: String = ""
    @State private var password: String = ""
    @State private var savedURLs: [String] = []
    @State private var showManual: Bool = false
    @FocusState private var focusField: Field?

    enum Field { case url, password }

    // The URL that's "selected" for connection (either from a card or manual entry)
    private var activeURL: String {
        serverURL.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo / title
            VStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                Text("Myrlin")
                    .font(.largeTitle.bold())
                Text("Claude Workspace Manager")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 36)

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

                // Separator with "or" label
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

            // Manual / new server entry
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
                        .onSubmit { Task { await login() } }
                }
            }
            .padding(.horizontal, 32)

            // Error
            if let error = appState.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 12)
            }

            // Connect button
            Button {
                Task { await login() }
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
        .onAppear {
            savedURLs = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
            if let saved = AuthService.shared.serverURL, !saved.isEmpty {
                serverURL = saved
                focusField = .password
            } else if savedURLs.isEmpty {
                focusField = .url
            }
        }
    }

    private func login() async {
        await appState.login(serverURL: activeURL, password: password)
        if appState.connectionError == nil {
            saveServerURL(activeURL)
            savedURLs = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
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

// MARK: - Server Card

private struct ServerCard: View {
    let url: String
    let isSelected: Bool
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
                // Server icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color(.tertiarySystemBackground))
                        .frame(width: 38, height: 38)
                    Image(systemName: isLocal ? "house.fill" : "cloud.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }

                // URL details
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayHost)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
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

                // Selection indicator
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
