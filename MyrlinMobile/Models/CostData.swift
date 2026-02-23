import Foundation

struct CostDashboard: Codable {
    var sessions: [SessionCostEntry]
    var total: Double
    var byWorkspace: [WorkspaceCost]
}

struct SessionCostEntry: Codable, Identifiable {
    var id: String
    var name: String
    var cost: Double
    var inputTokens: Int
    var outputTokens: Int
    var model: String?
}

struct WorkspaceCost: Codable, Identifiable {
    var id: String
    var name: String
    var cost: Double
}

struct QuotaOverview: Codable {
    var used: Double?
    var limit: Double?
    var percent: Double?
}

struct SubagentInfo: Codable, Identifiable {
    var id: String
    var type: String?
    var status: String?
    var description: String?
}

struct DiscoveredSession: Codable, Identifiable {
    var id: String
    var projectPath: String
    var lastUsed: Date?
    var messageCount: Int?
}

struct TunnelConfig: Codable, Identifiable {
    var id: String
    var name: String
    var url: String?
    var status: String?
}

struct NamedTunnel: Codable {
    var token: String?
    var domain: String?
    var status: String?
    var running: Bool
}
