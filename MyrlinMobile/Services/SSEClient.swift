import Foundation

/// Server-Sent Events client. Connects to /api/events and streams SSEEvent objects.
/// Auto-reconnects with exponential backoff on disconnect.
@MainActor
class SSEClient: ObservableObject {
    @Published var lastEvent: SSEEvent? = nil
    @Published var isConnected: Bool = false

    private var task: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0

    func connect() {
        guard let serverURL = AuthService.shared.serverURL,
              let token = AuthService.shared.token,
              let url = URL(string: "\(serverURL)/api/events?token=\(token)") else { return }

        task?.cancel()
        task = Task { [weak self] in
            await self?.streamLoop(url: url)
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
        isConnected = false
    }

    private func streamLoop(url: URL) async {
        while !Task.isCancelled {
            do {
                try await stream(url: url)
                reconnectDelay = 1.0
            } catch {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                reconnectDelay = min(reconnectDelay * 2, 30.0)
            }
        }
    }

    private func stream(url: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SSEError.badResponse
        }

        isConnected = true
        var dataLines: [String] = []

        for try await line in bytes.lines {
            if Task.isCancelled { break }

            if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                dataLines.append(data)
            } else if line.isEmpty && !dataLines.isEmpty {
                // Dispatch event
                let raw = dataLines.joined(separator: "\n")
                dataLines = []
                if raw == "[DONE]" { break }
                if let event = parseSSEData(raw) {
                    lastEvent = event
                }
            }
        }
        isConnected = false
    }

    private func parseSSEData(_ raw: String) -> SSEEvent? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        return SSEEvent(type: type, payload: json)
    }
}

struct SSEEvent {
    let type: String
    let payload: [String: Any]
}

enum SSEError: Error {
    case badResponse
}
