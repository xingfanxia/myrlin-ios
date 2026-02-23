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
                            Text(dashboard.total, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                        if let quota {
                            if let used = quota.used, let limit = quota.limit, limit > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    LabeledContent("Quota") {
                                        Text("\(used, format: .currency(code: "USD")) / \(limit, format: .currency(code: "USD"))")
                                            .foregroundStyle(.secondary)
                                    }
                                    ProgressView(value: min(used / limit, 1.0))
                                        .tint(used / limit > 0.8 ? .red : .blue)
                                }
                            }
                        }
                    }

                    if !dashboard.sessions.isEmpty {
                        Section("Top Sessions") {
                            ForEach(dashboard.sessions.sorted { $0.cost > $1.cost }) { entry in
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
                            ForEach(dashboard.byWorkspace.sorted { $0.cost > $1.cost }) { ws in
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
