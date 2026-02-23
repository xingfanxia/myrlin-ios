import Foundation

/// REST client for the Myrlin server API.
final class MyrlinAPI {
    static let shared = MyrlinAPI()
    private init() {}

    private var baseURL: String { AuthService.shared.serverURL ?? "" }
    private var token: String { AuthService.shared.token ?? "" }

    // MARK: - Generic Request

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Sessions

    func sessions(workspaceId: String? = nil) async throws -> [Session] {
        var path = "/api/sessions"
        if let id = workspaceId { path += "?workspaceId=\(id)" }
        struct Wrapper: Decodable { let sessions: [Session] }
        let wrapper: Wrapper = try await request(path)
        return wrapper.sessions
    }

    func createSession(name: String, workspaceId: String, workingDir: String? = nil) async throws -> Session {
        struct Body: Encodable { let name: String; let workspaceId: String; let workingDir: String? }
        struct Wrapper: Decodable { let session: Session }
        let wrapper: Wrapper = try await request("/api/sessions", method: "POST",
            body: Body(name: name, workspaceId: workspaceId, workingDir: workingDir))
        return wrapper.session
    }

    func startSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/start", method: "POST")
    }

    func stopSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/stop", method: "POST")
    }

    // MARK: - Workspaces

    func workspaces() async throws -> [Workspace] {
        struct Wrapper: Decodable { let workspaces: [Workspace] }
        let wrapper: Wrapper = try await request("/api/workspaces")
        return wrapper.workspaces
    }

    func createWorkspace(name: String, color: String? = nil) async throws -> Workspace {
        struct Body: Encodable { let name: String; let color: String? }
        struct Wrapper: Decodable { let workspace: Workspace }
        let wrapper: Wrapper = try await request("/api/workspaces", method: "POST",
            body: Body(name: name, color: color))
        return wrapper.workspace
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP \(code)"
        case .decodingError(let m): return "Decode error: \(m)"
        }
    }
}

// Type-erased Encodable wrapper
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
