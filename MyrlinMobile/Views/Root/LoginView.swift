import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var serverURL: String = "http://localhost:3456"
    @State private var password: String = ""
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
        .onAppear { focusField = .url }
    }

    private func login() async {
        await appState.login(serverURL: serverURL, password: password)
    }
}
