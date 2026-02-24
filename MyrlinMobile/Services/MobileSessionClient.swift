import Foundation
import Combine

/// WebSocket client connecting to /ws/mobile for claude stream-json sessions.
///
/// Architecture: one claude process per message turn on the server side.
/// The WebSocket stays open across turns; `isGenerating` is true while
/// a turn is in progress. The server sends `turn_complete` when done.
@MainActor
class MobileSessionClient: NSObject, ObservableObject {
    @Published var messages: [StreamMessage] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isGenerating: Bool = false
    @Published var error: String? = nil

    /// The Claude session ID used for --resume on subsequent turns.
    private(set) var claudeSessionId: String? = nil

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    enum ConnectionState {
        case disconnected, connecting, connected
    }

    // MARK: - Connect

    func connect(sessionId: String, resumeSessionId: String? = nil,
                 model: String? = nil, workingDir: String? = nil,
                 initialMessages: [StreamMessage] = []) {
        guard let serverURL = AuthService.shared.serverURL,
              let token = AuthService.shared.token else {
            error = "Not authenticated"
            return
        }

        connectionState = .connecting
        messages = initialMessages  // Restore cached history
        error = nil
        isGenerating = false
        claudeSessionId = resumeSessionId

        // Force IPv4 for localhost: iOS resolves "localhost" to ::1 (IPv6) first,
        // but Node.js listens on IPv4 only, causing connection refused.
        let resolvedURL = serverURL.replacingOccurrences(of: "://localhost", with: "://127.0.0.1")
        var components = URLComponents(string: "\(resolvedURL)/ws/mobile")!
        components.scheme = serverURL.hasPrefix("https") ? "wss" : "ws"
        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "sessionId", value: sessionId),
        ]
        if let resume = resumeSessionId { queryItems.append(URLQueryItem(name: "resumeSessionId", value: resume)) }
        if let m = model { queryItems.append(URLQueryItem(name: "model", value: m)) }
        if let dir = workingDir { queryItems.append(URLQueryItem(name: "workingDir", value: dir)) }
        components.queryItems = queryItems

        guard let url = components.url else {
            error = "Invalid WebSocket URL"
            connectionState = .disconnected
            return
        }

        print("[WS] Connecting to: \(url)")

        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()
        connectionState = .connected
        receiveNextMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession = nil
        connectionState = .disconnected
        isGenerating = false
    }

    // MARK: - Send

    func send(text: String) async throws {
        guard let task = webSocketTask, connectionState == .connected else {
            throw WSError.notConnected
        }
        guard !isGenerating else {
            throw WSError.turnInProgress
        }
        // Inject user message locally — the server never echoes it back
        messages.append(StreamMessage(localUserMessage: text))
        isGenerating = true
        let payload = ["type": "input", "content": text]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let line = String(data: json, encoding: .utf8)! + "\n"
        try await task.send(.string(line))
    }

    // MARK: - Receive Loop

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let msg):
                    self.handleMessage(msg)
                    self.receiveNextMessage()
                case .failure(let err):
                    if self.connectionState == .connected {
                        self.error = err.localizedDescription
                        self.connectionState = .disconnected
                        self.isGenerating = false
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            for line in text.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let data = line.data(using: .utf8) else { continue }
                processJSONData(data)
            }
        case .data(let data):
            processJSONData(data)
        @unknown default: break
        }
    }

    private func processJSONData(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Handle server-side turn_complete (from mobile-bridge, not Claude itself)
        if let type_ = obj["type"] as? String, type_ == "system",
           let subtype = obj["subtype"] as? String, subtype == "turn_complete" {
            isGenerating = false
            if let sid = obj["claudeSessionId"] as? String {
                claudeSessionId = sid
            }
            return
        }

        // Parse one JSONL line into zero or more renderable StreamMessages
        let parsed = StreamMessage.parseAll(from: data)
        messages.append(contentsOf: parsed)
    }
}

extension MobileSessionClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didOpenWithProtocol protocol: String?) {
        Task { @MainActor in self.connectionState = .connected }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.connectionState = .disconnected
            self.isGenerating = false
        }
    }
}

enum WSError: Error {
    case notConnected
    case turnInProgress

    var localizedDescription: String {
        switch self {
        case .notConnected: return "Not connected to server"
        case .turnInProgress: return "Please wait for the current response to finish"
        }
    }
}
