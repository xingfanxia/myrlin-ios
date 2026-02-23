import SwiftUI
import WebKit

/// Main session view with toggle between Chat (stream-json) and Terminal (WKWebView) modes.
struct MobileSessionView: View {
    let session: Session
    @StateObject private var client = MobileSessionClient()
    @State private var mode: ViewMode = .chat
    @State private var scrollToBottom: Bool = false

    enum ViewMode { case chat, terminal }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .chat:
                chatView
            case .terminal:
                terminalView
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { modeToggle }
        .onAppear { connectIfNeeded() }
        .onDisappear { client.disconnect() }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
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

                    // Invisible spacer at bottom for auto-scroll target
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: client.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom")
                    }
                }
            }

            // Stats bar (pinned above input)
            if let stats = latestStats {
                StatsBar(stats: stats)
            }

            // Input bar
            InputBar(
                isConnected: client.connectionState == .connected,
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

    // MARK: - Toolbar Toggle

    @ToolbarContentBuilder
    private var modeToggle: some ToolbarContent {
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

    private func connectIfNeeded() {
        guard client.connectionState == .disconnected else { return }
        client.connect(
            sessionId: session.id,
            resumeSessionId: session.claudeSessionId,
            workingDir: session.workingDir
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
        // Inject auth token into the web UI via JS
        let script = """
        window.__MYRLIN_TOKEN = '\(token.replacingOccurrences(of: "'", with: "\\'"))';
        window.__MYRLIN_SESSION_ID = '\(sessionId)';
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
