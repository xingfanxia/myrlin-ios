import Foundation

struct Workspace: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var color: String?
    var groupId: String?
    var sessionCount: Int?
    var createdAt: Date?
}

struct WorkspaceGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var color: String?
    var workspaces: [Workspace]
}
