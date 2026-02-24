import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL: String = "http://localhost:3456"
    @State private var password: String = ""
    @State private var savedURLs: [String] = []
    @FocusState private var focusField: Field?

    enum Field { case url, password }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo / title
            VStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("Myrlin")
                    .font(.largeTitle.bold())
                Text("Claude Workspace Manager")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Server URL").font(.caption).foregroundStyle(.secondary)
                    TextField("http://localhost:3456", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusField = .password }

                    if !savedURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(savedURLs, id: \.self) { url in
                                    Button(url.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")) {
                                        serverURL = url
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
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

            if let error = appState.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await login() }
            } label: {
                if appState.isConnecting {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(serverURL.isEmpty || password.isEmpty || appState.isConnecting)
            .padding(.horizontal, 32)

            Spacer()
        }
        .onAppear {
            if let saved = AuthService.shared.serverURL, !saved.isEmpty {
                serverURL = saved
            }
            focusField = serverURL.isEmpty ? .url : .password
            savedURLs = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
        }
    }

    private func login() async {
        await appState.login(serverURL: serverURL, password: password)
        if appState.connectionError == nil {
            saveServerURL(serverURL)
            savedURLs = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
        }
    }

    private func saveServerURL(_ url: String) {
        guard !url.isEmpty else { return }
        var saved = UserDefaults.standard.stringArray(forKey: "savedServerURLs") ?? []
        saved.removeAll { $0 == url }
        saved.insert(url, at: 0)
        UserDefaults.standard.set(Array(saved.prefix(3)), forKey: "savedServerURLs")
    }
}
