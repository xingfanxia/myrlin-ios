import SwiftUI

struct TunnelView: View {
    @State private var namedTunnel: NamedTunnel? = nil
    @State private var tunnels: [TunnelConfig] = []
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var tokenInput = ""
    @State private var isSavingToken = false
    @State private var isStartingTunnel = false
    @State private var isStoppingTunnel = false
    @State private var showNewTunnel = false
    @State private var newTunnelName = ""
    @State private var isCreatingTunnel = false
    @State private var actionError: String? = nil

    var body: some View {
        Form {
            // Named tunnel section
            Section("Cloudflare Named Tunnel") {
                if let tunnel = namedTunnel {
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(tunnel.running ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(tunnel.running ? "Running" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let domain = tunnel.domain {
                        LabeledContent("Domain") {
                            Text(domain)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    HStack {
                        SecureField("Cloudflare tunnel token", text: $tokenInput)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                        Button("Save") {
                            Task { await saveToken() }
                        }
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || isSavingToken)
                        if isSavingToken { ProgressView().scaleEffect(0.7) }
                    }
                    HStack(spacing: 12) {
                        Button {
                            Task { await startNamedTunnel() }
                        } label: {
                            Label("Start", systemImage: "play.circle.fill")
                        }
                        .disabled(tunnel.running || isStartingTunnel || isStoppingTunnel)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            Task { await stopNamedTunnel() }
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                        .disabled(!tunnel.running || isStartingTunnel || isStoppingTunnel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)

                        if isStartingTunnel || isStoppingTunnel {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Ad-hoc tunnels section
            Section("Ad-hoc Tunnels") {
                if tunnels.isEmpty && !isLoading {
                    Text("No tunnels created")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(tunnels) { tunnel in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tunnel.name)
                                if let url = tunnel.url {
                                    Text(url)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if let url = tunnel.url {
                                Button {
                                    UIPasteboard.general.string = url
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                    .onDelete { indices in
                        let toDelete = indices.map { tunnels[$0] }
                        Task {
                            for t in toDelete {
                                try? await MyrlinAPI.shared.deleteTunnel(t.id)
                            }
                            await loadTunnels()
                        }
                    }
                }
            }

            if let err = actionError {
                Section {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Tunnels")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNewTunnel = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("New Tunnel", isPresented: $showNewTunnel) {
            TextField("Tunnel name", text: $newTunnelName)
            Button("Create") {
                Task { await createTunnel() }
            }
            .disabled(newTunnelName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { newTunnelName = "" }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        async let named = try? MyrlinAPI.shared.namedTunnel()
        async let ts = try? MyrlinAPI.shared.tunnels()
        let (n, t) = await (named, ts)
        namedTunnel = n
        tunnels = t ?? []
        if n == nil && t == nil { error = "Failed to load tunnel info" }
        isLoading = false
    }

    private func loadTunnels() async {
        if let ts = try? await MyrlinAPI.shared.tunnels() {
            tunnels = ts
        }
    }

    private func saveToken() async {
        let tok = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !tok.isEmpty else { return }
        isSavingToken = true
        actionError = nil
        do {
            try await MyrlinAPI.shared.configureNamedTunnel(token: tok)
            tokenInput = ""
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isSavingToken = false
    }

    private func startNamedTunnel() async {
        isStartingTunnel = true
        actionError = nil
        do {
            try await MyrlinAPI.shared.startNamedTunnel()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isStartingTunnel = false
    }

    private func stopNamedTunnel() async {
        isStoppingTunnel = true
        actionError = nil
        do {
            try await MyrlinAPI.shared.stopNamedTunnel()
            await load()
        } catch {
            actionError = error.localizedDescription
        }
        isStoppingTunnel = false
    }

    private func createTunnel() async {
        let name = newTunnelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingTunnel = true
        actionError = nil
        do {
            let tunnel = try await MyrlinAPI.shared.createTunnel(name: name)
            tunnels.append(tunnel)
        } catch {
            actionError = error.localizedDescription
        }
        newTunnelName = ""
        isCreatingTunnel = false
    }
}
