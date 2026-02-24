import SwiftUI
import WebKit

/// Main session view with toggle between Chat (stream-json) and Terminal (WKWebView) modes.
struct MobileSessionView: View {
    let session: Session
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var client = MobileSessionClient()
    @State private var mode: ViewMode = .chat
    @State private var scrollToBottom: Bool = false
    @State private var showDetail: Bool = false

    enum ViewMode { case chat, terminal }

    /// Live session from AppState (updated by SSE), falling back to the initial value
    private var liveSession: Session {
        appState.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .chat:
                chatView
            case .terminal:
                terminalView
            }
        }
        .navigationTitle(liveSession.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { Task { await connectIfNeeded() } }
        .onDisappear {
            // Save messages to cache before disconnecting so they survive navigation
            if !client.messages.isEmpty {
                appState.messageCache[session.id] = client.messages
            }
            client.disconnect()
        }
        // Auto-pop when this session is deleted (from the info panel or elsewhere)
        .onChange(of: appState.sessions) { sessions in
            if !sessions.contains(where: { $0.id == session.id }) {
                dismiss()
            }
        }
        .sheet(isPresented: $showDetail) {
            SessionDetailView(session: liveSession)
                .environmentObject(appState)
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Connection status banner
            if client.connectionState == .connecting {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Connecting…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))
            } else if let err = client.error {
                Text("⚠ \(err)").font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.systemGroupedBackground))
            }

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(client.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: client.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom")
                    }
                }
                .overlay {
                    if client.messages.isEmpty && client.connectionState == .connected && client.error == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "message").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("Session ready")
                                .font(.headline).foregroundStyle(.secondary)
                            Text("Type a message below to start, or switch to Terminal mode to view the existing PTY session.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                }
            }

            // Generating indicator
            if client.isGenerating {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Claude is thinking…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // Stats bar (pinned above input)
            if let stats = latestStats {
                StatsBar(stats: stats)
            }

            // Input bar — disabled while Claude is generating a response
            InputBar(
                isConnected: client.connectionState == .connected && !client.isGenerating,
                onSend: { text in
                    Task { try? await client.send(text: text) }
                }
            )
        }
    }

    // MARK: - Terminal View (WKWebView fallback)

    private var terminalView: some View {
        TerminalWebView(serverURL: AuthService.shared.serverURL ?? "",
                        token: AuthService.shared.token ?? "",
                        sessionId: session.id)
            .edgesIgnoringSafeArea(.bottom)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showDetail = true
            } label: {
                Image(systemName: "info.circle")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Picker("Mode", selection: $mode) {
                Label("Chat", systemImage: "message").tag(ViewMode.chat)
                Label("Terminal", systemImage: "terminal").tag(ViewMode.terminal)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
        }
    }

    // MARK: - Helpers

    private func connectIfNeeded() async {
        guard client.connectionState == .disconnected else { return }

        // Use cached messages if available. Otherwise load from server JSONL
        // when the session has a claudeSessionId (i.e. it has prior history).
        var initialMessages = appState.messageCache[session.id] ?? []
        if initialMessages.isEmpty, let _ = liveSession.claudeSessionId {
            let lines = (try? await MyrlinAPI.shared.sessionHistory(session.id)) ?? []
            for line in lines {
                if let data = line.data(using: .utf8) {
                    initialMessages.append(contentsOf: StreamMessage.parseAll(from: data))
                }
            }
        }

        // Use liveSession so we pick up claudeSessionId/workingDir set after creation
        client.connect(
            sessionId: liveSession.id,
            resumeSessionId: liveSession.claudeSessionId,
            workingDir: liveSession.workingDir,
            initialMessages: initialMessages
        )
    }

    private var latestStats: StreamMessage? {
        client.messages.last { msg in
            if case .stats = msg.type { return true }
            return false
        }
    }
}

/// WKWebView wrapper that loads the existing Myrlin web terminal UI.
struct TerminalWebView: UIViewRepresentable {
    let serverURL: String
    let token: String
    let sessionId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Inject auth token into localStorage before the app JS runs.
        // The web app reads localStorage.getItem('cwm_token') on startup.
        let safeToken = token.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
        let safeSessionId = sessionId.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        localStorage.setItem('cwm_token', '\(safeToken)');
        window.__MYRLIN_SESSION_ID = '\(safeSessionId)';
        """
        let userScript = WKUserScript(source: script,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        let wv = WKWebView(frame: .zero, configuration: config)
        if let url = URL(string: "\(serverURL)/#session/\(sessionId)") {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
