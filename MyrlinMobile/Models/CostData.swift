import Foundation

// MARK: - Cost Dashboard
// Server: GET /api/cost/dashboard → { summary: {...}, sessions: [...], byWorkspace: [...] }

struct CostDashboard: Codable {
    var summary: CostSummary
    var sessions: [SessionCostEntry]
    var byWorkspace: [WorkspaceCost]

    struct CostSummary: Codable {
        var totalCost: Double
        var periodCost: Double?
        var periodLabel: String?
        var messageCount: Int?
        var cacheSavings: Double?
        var totalTokens: TotalTokens?

        struct TotalTokens: Codable {
            var input: Int?
            var output: Int?
            var cacheRead: Int?
            var cacheWrite: Int?
        }
    }
}

struct SessionCostEntry: Codable, Identifiable {
    var id: String
    var name: String
    var cost: Double
    var messageCount: Int?
    var model: String?
}

struct WorkspaceCost: Codable, Identifiable {
    var id: String
    var name: String
    var cost: Double
    var sessionCount: Int?
}

// MARK: - Quota Overview
// Server: GET /api/quota-overview → { summary: { totalSessions, criticalCount, ... }, sessions: [...] }

struct QuotaOverview: Codable {
    var summary: QuotaSummary?
    var sessions: [SessionQuota]?

    struct QuotaSummary: Codable {
        var totalSessions: Int?
        var criticalCount: Int?
        var warningCount: Int?
        var totalCost: Double?
    }

    struct SessionQuota: Codable {
        var sessionId: String?
        var sessionName: String?
        var contextPct: Int?
        var urgency: String?   // "ok" | "warning" | "critical"
        var totalCost: Double?
        var latestInputTokens: Int?
    }
}

// MARK: - Subagent

struct SubagentInfo: Codable, Identifiable {
    var id: String
    var type: String?
    var status: String?
    var description: String?
}

// MARK: - Discover
// Server: GET /api/discover → { projects: [{encodedName, realPath, sessionCount, lastActive, ...}] }

struct DiscoveredProject: Codable, Identifiable {
    var encodedName: String
    var realPath: String
    var sessionCount: Int
    var lastActive: Date?
    var hasClaudeMd: Bool?
    var dirExists: Bool?
    /// All JSONL sessions for this project, sorted newest-first by the server.
    var sessions: [DiscoveredSession]?

    /// The most recent Claude session UUID (JSONL filename without extension).
    var latestSessionId: String? { sessions?.first?.name }

    // Use encodedName as stable ID
    var id: String { encodedName }
}

struct DiscoveredSession: Codable {
    var name: String       // Claude session UUID (= JSONL filename without .jsonl)
    var modified: Date?
    var size: Int?
}

// MARK: - Tunnels

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
