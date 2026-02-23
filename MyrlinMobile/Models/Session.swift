import Foundation

struct Session: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var status: SessionStatus
    var workspaceId: String?
    var workingDir: String?
    var claudeSessionId: String?
    var lastActive: Date?
    var createdAt: Date?

    enum SessionStatus: String, Codable {
        case running, stopped, error, unknown
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, workspaceId, workingDir, claudeSessionId, lastActive, createdAt
    }
}
