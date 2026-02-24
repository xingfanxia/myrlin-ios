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
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                AuthService.shared.logout()
                NotificationCenter.default.post(name: .myrlinTokenExpired, object: nil)
                throw APIError.tokenExpired
            }
            throw APIError.httpError(code)
        }
        return try decode(T.self, from: data)
    }

    /// DELETE request that expects no response body (204 or empty 200).
    private func deleteRequest(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                AuthService.shared.logout()
                NotificationCenter.default.post(name: .myrlinTokenExpired, object: nil)
                throw APIError.tokenExpired
            }
            throw APIError.httpError(code)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso.date(from: str) { return date }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let date = iso2.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Invalid ISO8601 date: \(str)")
        }
        return try decoder.decode(type, from: data)
    }

    // MARK: - Auth

    func checkAuth() async throws -> Bool {
        struct AuthCheck: Decodable { let authenticated: Bool }
        guard let url = URL(string: "\(baseURL)/api/auth/check") else { return false }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return false }
        if http.statusCode == 401 {
            AuthService.shared.logout()
            NotificationCenter.default.post(name: .myrlinTokenExpired, object: nil)
            return false
        }
        return (try? JSONDecoder().decode(AuthCheck.self, from: data))?.authenticated ?? false
    }

    // MARK: - Sessions

    func sessions(workspaceId: String? = nil) async throws -> [Session] {
        var path = "/api/sessions"
        if let id = workspaceId { path += "?workspaceId=\(id)" }
        struct Wrapper: Decodable { let sessions: [Session] }
        let wrapper: Wrapper = try await request(path)
        return wrapper.sessions
    }

    func createSession(name: String, workspaceId: String, workingDir: String? = nil,
                       model: String? = nil, bypassPermissions: Bool? = nil,
                       verbose: Bool? = nil, agentTeams: Bool? = nil,
                       claudeSessionId: String? = nil) async throws -> Session {
        struct Body: Encodable {
            let name: String; let workspaceId: String; let workingDir: String?
            let model: String?; let bypassPermissions: Bool?; let verbose: Bool?
            let agentTeams: Bool?; let claudeSessionId: String?
        }
        struct Wrapper: Decodable { let session: Session }
        let wrapper: Wrapper = try await request("/api/sessions", method: "POST",
            body: Body(name: name, workspaceId: workspaceId, workingDir: workingDir,
                       model: model, bypassPermissions: bypassPermissions,
                       verbose: verbose, agentTeams: agentTeams,
                       claudeSessionId: claudeSessionId))
        return wrapper.session
    }

    func updateSession(_ id: String, name: String? = nil, tags: [String]? = nil) async throws -> Session {
        struct Body: Encodable { let name: String?; let tags: [String]? }
        struct Wrapper: Decodable { let session: Session }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)", method: "PATCH",
            body: Body(name: name, tags: tags))
        return wrapper.session
    }

    func deleteSession(_ id: String) async throws {
        try await deleteRequest("/api/sessions/\(id)")
    }

    func startSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/start", method: "POST")
    }

    func stopSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/stop", method: "POST")
    }

    func restartSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/restart", method: "POST")
    }

    /// Creates a git worktree + session atomically via POST /api/worktree-tasks.
    /// The session is added to AppState automatically via SSE session:created.
    func createWorktreeTask(workspaceId: String, repoDir: String, branch: String,
                            description: String, baseBranch: String = "main",
                            model: String? = nil) async throws {
        struct Body: Encodable {
            let workspaceId: String; let repoDir: String; let branch: String
            let description: String; let baseBranch: String; let model: String?
        }
        struct AnyResponse: Decodable {}
        let _: AnyResponse = try await request("/api/worktree-tasks", method: "POST",
            body: Body(workspaceId: workspaceId, repoDir: repoDir, branch: branch,
                       description: description, baseBranch: baseBranch, model: model))
    }

    func sessionCost(_ id: String) async throws -> SessionCost {
        struct Wrapper: Decodable { let cost: SessionCost }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/cost")
        return wrapper.cost
    }

    func serverLogout() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/auth/logout", method: "POST")
    }

    func autoTitle(_ id: String) async throws -> String {
        struct Wrapper: Decodable { let name: String }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/auto-title", method: "POST")
        return wrapper.name
    }

    func summarizeSession(_ id: String) async throws -> String {
        struct Wrapper: Decodable { let summary: String }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/summarize", method: "POST")
        return wrapper.summary
    }

    func extractTasks(_ id: String) async throws -> [String] {
        struct Wrapper: Decodable { let tasks: [String] }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/extract-tasks", method: "POST")
        return wrapper.tasks
    }

    func subagents(_ id: String) async throws -> [SubagentInfo] {
        struct Wrapper: Decodable { let subagents: [SubagentInfo] }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/subagents")
        return wrapper.subagents
    }

    func exportContext(_ id: String) async throws -> String {
        struct Wrapper: Decodable { let context: String }
        let wrapper: Wrapper = try await request("/api/sessions/\(id)/export-context")
        return wrapper.context
    }

    func refocusSession(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/sessions/\(id)/refocus", method: "POST")
    }

    func costDashboard(period: String = "month") async throws -> CostDashboard {
        let wrapper: CostDashboard = try await request("/api/cost/dashboard?period=\(period)")
        return wrapper
    }

    func quotaOverview() async throws -> QuotaOverview {
        let wrapper: QuotaOverview = try await request("/api/quota-overview")
        return wrapper
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

    func updateWorkspace(_ id: String, name: String? = nil, color: String? = nil, description: String? = nil) async throws -> Workspace {
        struct Body: Encodable { let name: String?; let color: String?; let description: String? }
        struct Wrapper: Decodable { let workspace: Workspace }
        let wrapper: Wrapper = try await request("/api/workspaces/\(id)", method: "PATCH",
            body: Body(name: name, color: color, description: description))
        return wrapper.workspace
    }

    func deleteWorkspace(_ id: String) async throws {
        try await deleteRequest("/api/workspaces/\(id)")
    }

    func activateWorkspace(_ id: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/\(id)/activate", method: "POST")
    }

    // MARK: - Workspace Docs

    func getWorkspaceDocs(_ id: String) async throws -> WorkspaceDocs {
        struct Wrapper: Decodable { let docs: WorkspaceDocs }
        let wrapper: Wrapper = try await request("/api/workspaces/\(id)/docs")
        return wrapper.docs
    }

    func toggleWorkspaceTask(_ workspaceId: String, index: Int) async throws {
        struct Body: Encodable { let index: Int }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/\(workspaceId)/docs/tasks/\(index)/toggle",
            method: "POST")
    }

    func updateWorkspaceDocs(_ id: String, docs: WorkspaceDocs) async throws -> WorkspaceDocs {
        struct Wrapper: Decodable { let docs: WorkspaceDocs }
        let wrapper: Wrapper = try await request("/api/workspaces/\(id)/docs", method: "PUT", body: docs)
        return wrapper.docs
    }

    func addDocsEntry(_ wsId: String, section: String, text: String) async throws {
        struct Body: Encodable { let text: String }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/\(wsId)/docs/\(section)", method: "POST",
            body: Body(text: text))
    }

    func editDocsEntry(_ wsId: String, section: String, index: Int, text: String) async throws {
        struct Body: Encodable { let text: String }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/\(wsId)/docs/\(section)/\(index)", method: "PUT",
            body: Body(text: text))
    }

    func deleteDocsEntry(_ wsId: String, section: String, index: Int) async throws {
        try await deleteRequest("/api/workspaces/\(wsId)/docs/\(section)/\(index)")
    }

    func reorderWorkspaces(_ ids: [String]) async throws {
        struct Body: Encodable { let order: [String] }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/reorder", method: "PUT",
            body: Body(order: ids))
    }

    // MARK: - Groups

    func groups() async throws -> [WorkspaceGroup] {
        struct Wrapper: Decodable { let groups: [WorkspaceGroup] }
        let wrapper: Wrapper = try await request("/api/groups")
        return wrapper.groups
    }

    func createGroup(name: String, color: String? = nil) async throws -> WorkspaceGroup {
        struct Body: Encodable { let name: String; let color: String? }
        struct Wrapper: Decodable { let group: WorkspaceGroup }
        let wrapper: Wrapper = try await request("/api/groups", method: "POST",
            body: Body(name: name, color: color))
        return wrapper.group
    }

    func updateGroup(_ id: String, name: String) async throws -> WorkspaceGroup {
        struct Body: Encodable { let name: String }
        struct Wrapper: Decodable { let group: WorkspaceGroup }
        let wrapper: Wrapper = try await request("/api/groups/\(id)", method: "PATCH",
            body: Body(name: name))
        return wrapper.group
    }

    func deleteGroup(_ id: String) async throws {
        try await deleteRequest("/api/groups/\(id)")
    }

    func addWorkspaceToGroup(workspaceId: String, groupId: String) async throws {
        struct Body: Encodable { let groupId: String }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/workspaces/\(workspaceId)/group", method: "PUT",
            body: Body(groupId: groupId))
    }

    // MARK: - Discover

    func discoverProjects() async throws -> [DiscoveredProject] {
        struct Wrapper: Decodable { let projects: [DiscoveredProject] }
        let wrapper: Wrapper = try await request("/api/discover")
        return wrapper.projects
    }

    // MARK: - Tunnels

    func tunnels() async throws -> [TunnelConfig] {
        struct Wrapper: Decodable { let tunnels: [TunnelConfig] }
        let wrapper: Wrapper = try await request("/api/tunnels")
        return wrapper.tunnels
    }

    func createTunnel(name: String) async throws -> TunnelConfig {
        struct Body: Encodable { let name: String }
        struct Wrapper: Decodable { let tunnel: TunnelConfig }
        let wrapper: Wrapper = try await request("/api/tunnels", method: "POST",
            body: Body(name: name))
        return wrapper.tunnel
    }

    func deleteTunnel(_ id: String) async throws {
        try await deleteRequest("/api/tunnels/\(id)")
    }

    func namedTunnel() async throws -> NamedTunnel {
        let wrapper: NamedTunnel = try await request("/api/tunnel/named")
        return wrapper
    }

    func configureNamedTunnel(token: String) async throws {
        struct Body: Encodable { let token: String }
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/tunnel/named/config", method: "PUT",
            body: Body(token: token))
    }

    func startNamedTunnel() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/tunnel/named/start", method: "POST")
    }

    func stopNamedTunnel() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await request("/api/tunnel/named/stop", method: "POST")
    }

    func searchSessions(query: String) async throws -> SearchResults {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        let results: SearchResults = try await request("/api/search?q=\(encoded)")
        return results
    }
}

// MARK: - Error types

enum APIError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case tokenExpired
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP \(code)"
        case .tokenExpired: return "Session expired — please log in again"
        case .decodingError(let m): return "Decode error: \(m)"
        }
    }
}

extension Notification.Name {
    static let myrlinTokenExpired = Notification.Name("myrlinTokenExpired")
}

// Type-erased Encodable wrapper
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
