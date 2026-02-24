import SwiftUI

struct CostView: View {
    @State private var period = "month"
    @State private var dashboard: CostDashboard? = nil
    @State private var quota: QuotaOverview? = nil
    @State private var isLoading = false
    @State private var error: String? = nil

    private let periods = ["day", "week", "month", "all"]

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(periods, id: \.self) { p in
                        Text(p.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            if isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if let error {
                Section {
                    Text(error).foregroundStyle(.red).font(.caption)
                    Button("Retry") { Task { await load() } }
                }
            } else {
                if let dashboard {
                    Section("Summary") {
                        LabeledContent("Total Cost") {
                            Text(dashboard.summary.totalCost, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                        if let period = dashboard.summary.periodLabel {
                            LabeledContent("Period") {
                                Text(period).foregroundStyle(.secondary)
                            }
                        }
                        if let msgs = dashboard.summary.messageCount {
                            LabeledContent("Messages") {
                                Text(msgs.formatted()).foregroundStyle(.secondary)
                            }
                        }
                        if let savings = dashboard.summary.cacheSavings, savings > 0 {
                            LabeledContent("Cache Savings") {
                                Text(savings, format: .currency(code: "USD"))
                                    .foregroundStyle(.green)
                            }
                        }
                        // Quota context bar
                        if let quota, let sessions = quota.sessions, !sessions.isEmpty {
                            let critical = sessions.filter { $0.urgency == "critical" }.count
                            let warning = sessions.filter { $0.urgency == "warning" }.count
                            if critical > 0 || warning > 0 {
                                HStack(spacing: 6) {
                                    if critical > 0 {
                                        Label("\(critical) critical", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    if warning > 0 {
                                        Label("\(warning) warning", systemImage: "exclamationmark.triangle")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }

                    if !dashboard.sessions.isEmpty {
                        Section("Top Sessions") {
                            ForEach(dashboard.sessions.prefix(10)) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name).lineLimit(1)
                                        if let model = entry.model {
                                            Text(model).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(entry.cost, format: .currency(code: "USD"))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !dashboard.byWorkspace.isEmpty {
                        Section("By Workspace") {
                            ForEach(dashboard.byWorkspace) { ws in
                                LabeledContent(ws.name) {
                                    Text(ws.cost, format: .currency(code: "USD"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Usage & Cost")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: period) { _ in Task { await load() } }
    }

    private func load() async {
        isLoading = true
        error = nil
        async let dash = try? MyrlinAPI.shared.costDashboard(period: period)
        async let q = try? MyrlinAPI.shared.quotaOverview()
        let (d, qv) = await (dash, q)
        dashboard = d
        quota = qv
        if d == nil { error = "Failed to load cost data" }
        isLoading = false
    }
}
