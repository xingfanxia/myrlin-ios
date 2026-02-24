import Foundation

struct Session: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var status: SessionStatus
    var workspaceId: String?
    var workingDir: String?
    var claudeSessionId: String?
    var lastActive: Date?
    var createdAt: Date?
    var tags: [String]?
    var model: String?

    enum SessionStatus: String, Codable {
        case running, stopped, error, unknown
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, workspaceId, workingDir, lastActive, createdAt, tags, model
        // Server stores the Claude session UUID as "resumeSessionId"
        case claudeSessionId = "resumeSessionId"
    }
}

struct SessionCost: Codable {
    var totalTokens: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var estimatedCost: Double?
}

struct SearchResult: Codable, Identifiable {
    var id: String
    var type: String   // "session" | "workspace" | "docs"
    var title: String
    var subtitle: String?
    var sessionId: String?
    var workspaceId: String?
}

struct SearchResults: Codable {
    var results: [SearchResult]
    var total: Int?
}
