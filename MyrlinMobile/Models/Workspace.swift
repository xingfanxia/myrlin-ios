import Foundation

struct Workspace: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var color: String?
    var groupId: String?
    var sessionCount: Int?
    var isActive: Bool?
    var description: String?
    var createdAt: Date?
}

struct WorkspaceGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var color: String?
    var workspaceIds: [String]?

    // Convenience: not from server, computed in view
    var workspaces: [Workspace] = []

    enum CodingKeys: String, CodingKey {
        case id, name, color, workspaceIds
    }
}

struct WorkspaceDocs: Codable {
    var notes: String?
    var goals: [String]?
    var tasks: [WorkspaceTask]?
    var roadmap: String?
    var rules: String?
}

struct WorkspaceTask: Identifiable {
    let index: Int   // positional index used for toggle API
    var text: String
    var done: Bool

    var id: Int { index }
}

extension WorkspaceTask: Codable {
    enum CodingKeys: String, CodingKey {
        case index, text, done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `index` may be absent if the server returns positional arrays
        index = (try? c.decode(Int.self, forKey: .index)) ?? 0
        text = try c.decode(String.self, forKey: .text)
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
    }
}
