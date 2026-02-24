import Foundation
import Combine

/// Central application state: auth credentials, server URL, live workspaces/sessions, and SSE routing.
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var serverURL: String = ""
    @Published var isConnecting: Bool = false
    @Published var connectionError: String? = nil

    // Live data — populated on login, mutated by SSE events
    @Published var workspaces: [Workspace] = []
    @Published var sessions: [Session] = []
    @Published var groups: [WorkspaceGroup] = []

    // Loading flags
    @Published var workspacesLoaded: Bool = false
    @Published var sessionsLoaded: Bool = false

    // In-memory message cache: session ID → messages
    // Persists across navigation so chat history is visible on re-open
    var messageCache: [String: [StreamMessage]] = [:]

    private let authService = AuthService.shared
    private let sseClient = SSEClient()
    private var tokenExpiredObserver: AnyCancellable?
    private var sseObserver: AnyCancellable?

    init() {
        // Restore auth state from Keychain on launch
        if let savedURL = authService.serverURL, let _ = authService.token {
            serverURL = savedURL
            isAuthenticated = true
            // Load data and connect SSE on next run loop so @Published is set up
            Task { @MainActor in
                await self.initialLoad()
                self.startSSE()
            }
        }
        // Auto-logout when any API call gets a 401 (server restarted, token wiped)
        tokenExpiredObserver = NotificationCenter.default
            .publisher(for: .myrlinTokenExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.logout() }
    }

    // MARK: - Auth

    func verifyTokenIfNeeded() {
        guard isAuthenticated else { return }
        Task {
            do {
                let valid: Bool = try await MyrlinAPI.shared.checkAuth()
                if !valid { logout() }
            } catch {
                // Network unavailable — don't log out
            }
        }
    }

    func login(serverURL: String, password: String) async {
        isConnecting = true
        connectionError = nil
        do {
            try await authService.login(serverURL: serverURL, password: password)
            self.serverURL = serverURL
            isAuthenticated = true
            await initialLoad()
            startSSE()
        } catch {
            connectionError = error.localizedDescription
        }
        isConnecting = false
    }

    func logout() {
        sseClient.disconnect()
        sseObserver?.cancel()
        Task { try? await MyrlinAPI.shared.serverLogout() }
        authService.logout()
        isAuthenticated = false
        serverURL = ""
        workspaces = []
        sessions = []
        groups = []
        workspacesLoaded = false
        sessionsLoaded = false
    }

    // MARK: - Initial Load

    func initialLoad() async {
        async let ws: [Workspace] = (try? MyrlinAPI.shared.workspaces()) ?? []
        async let ss: [Session] = (try? MyrlinAPI.shared.sessions()) ?? []
        async let grps: [WorkspaceGroup] = (try? MyrlinAPI.shared.groups()) ?? []
        let (fetchedWS, fetchedSS, fetchedGrps) = await (ws, ss, grps)
        workspaces = fetchedWS
        sessions = fetchedSS
        groups = fetchedGrps
        workspacesLoaded = true
        sessionsLoaded = true
    }

    func refreshWorkspaces() async {
        if let ws = try? await MyrlinAPI.shared.workspaces() { workspaces = ws }
    }

    func refreshSessions(workspaceId: String? = nil) async {
        if let ss = try? await MyrlinAPI.shared.sessions(workspaceId: workspaceId) {
            if let wid = workspaceId {
                sessions.removeAll { $0.workspaceId == wid }
                sessions.append(contentsOf: ss)
            } else {
                sessions = ss
            }
        }
    }

    // MARK: - SSE

    private func startSSE() {
        sseClient.connect()
        sseObserver = sseClient.$lastEvent
            .compactMap { $0 }
            .sink { [weak self] event in
                Task { @MainActor in self?.handle(event: event) }
            }
    }

    private func handle(event: SSEEvent) {
        switch event.type {

        // --- Session events ---
        case "session:created":
            if let session = event.decodePayload(Session.self, key: "session") {
                sessions.removeAll { $0.id == session.id }
                sessions.append(session)
            }
        case "session:updated":
            if let session = event.decodePayload(Session.self, key: "session") {
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx] = session
                }
            }
        case "session:deleted":
            if let id = event.payload["sessionId"] as? String {
                sessions.removeAll { $0.id == id }
            }

        // --- Workspace events ---
        case "workspace:created":
            if let ws = event.decodePayload(Workspace.self, key: "workspace") {
                workspaces.removeAll { $0.id == ws.id }
                workspaces.append(ws)
            }
        case "workspace:updated":
            if let ws = event.decodePayload(Workspace.self, key: "workspace") {
                if let idx = workspaces.firstIndex(where: { $0.id == ws.id }) {
                    workspaces[idx] = ws
                }
            }
        case "workspace:deleted":
            if let id = event.payload["workspaceId"] as? String {
                workspaces.removeAll { $0.id == id }
            }
        case "workspace:activated":
            if let id = event.payload["workspaceId"] as? String {
                for idx in workspaces.indices {
                    workspaces[idx].isActive = (workspaces[idx].id == id)
                }
            }
        case "workspaces:reordered":
            if let ids = event.payload["order"] as? [String] {
                let map = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
                workspaces = ids.compactMap { map[$0] }
            }

        // --- Group events ---
        case "group:created":
            if let grp = event.decodePayload(WorkspaceGroup.self, key: "group") {
                groups.removeAll { $0.id == grp.id }
                groups.append(grp)
            }
        case "group:updated":
            if let grp = event.decodePayload(WorkspaceGroup.self, key: "group") {
                if let idx = groups.firstIndex(where: { $0.id == grp.id }) {
                    groups[idx] = grp
                }
            }
        case "group:deleted":
            if let id = event.payload["groupId"] as? String {
                groups.removeAll { $0.id == id }
                // Ungroup workspaces that belonged to this group
                for idx in workspaces.indices where workspaces[idx].groupId == id {
                    workspaces[idx].groupId = nil
                }
            }

        default:
            break
        }
    }
}

// MARK: - SSEEvent decoding helper

extension SSEEvent {
    func decodePayload<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let obj = payload[key],
              let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
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
        return try? decoder.decode(T.self, from: data)
    }
}
