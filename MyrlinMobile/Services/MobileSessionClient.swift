import Foundation
import Combine

/// WebSocket client connecting to /ws/mobile for claude stream-json sessions.
@MainActor
class MobileSessionClient: NSObject, ObservableObject {
    @Published var messages: [StreamMessage] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var error: String? = nil

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    enum ConnectionState {
        case disconnected, connecting, connected
    }

    // MARK: - Connect

    func connect(sessionId: String, resumeSessionId: String? = nil,
                 model: String? = nil, workingDir: String? = nil) {
        guard let serverURL = AuthService.shared.serverURL,
              let token = AuthService.shared.token else {
            error = "Not authenticated"
            return
        }

        connectionState = .connecting
        messages = []
        error = nil

        var components = URLComponents(string: "\(serverURL)/ws/mobile")!
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
    }

    // MARK: - Send

    func send(text: String) async throws {
        guard let task = webSocketTask, connectionState == .connected else {
            throw WSError.notConnected
        }
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
                if let streamMsg = try? JSONDecoder().decode(StreamMessage.self, from: data) {
                    messages.append(streamMsg)
                }
            }
        case .data(let data):
            if let streamMsg = try? JSONDecoder().decode(StreamMessage.self, from: data) {
                messages.append(streamMsg)
            }
        @unknown default: break
        }
    }
}

extension MobileSessionClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didOpenWithProtocol protocol: String?) {
        Task { @MainActor in self.connectionState = .connected }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                     didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in self.connectionState = .disconnected }
    }
}

enum WSError: Error {
    case notConnected
}
