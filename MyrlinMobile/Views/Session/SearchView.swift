import SwiftUI
import Combine

struct SearchView: View {
    var workspaceId: String? = nil
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: SearchResults? = nil
    @State private var isSearching = false
    @State private var error: String? = nil
    @State private var debounceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("Search Sessions",
                        systemImage: "magnifyingglass",
                        description: Text("Type to search sessions, workspaces, and docs."))
                } else if isSearching {
                    VStack { Spacer(); ProgressView("Searching…"); Spacer() }
                } else if let error {
                    ContentUnavailableView("Search Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error))
                } else if let results, !results.results.isEmpty {
                    resultsList(results.results)
                } else if results != nil {
                    ContentUnavailableView("No Results",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No results for \"\(query)\""))
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Sessions, workspaces, docs…")
            .onChange(of: query) { newValue in
                debounceTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = nil; return
                }
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await performSearch(newValue)
                }
            }
        }
    }

    @ViewBuilder
    private func resultsList(_ items: [SearchResult]) -> some View {
        List {
            let sessions = items.filter { $0.type == "session" }
            let workspaces = items.filter { $0.type == "workspace" }
            let docs = items.filter { $0.type == "docs" }

            if !sessions.isEmpty {
                Section("Sessions") {
                    ForEach(sessions) { result in
                        resultRow(result)
                    }
                }
            }
            if !workspaces.isEmpty {
                Section("Workspaces") {
                    ForEach(workspaces) { result in
                        resultRow(result)
                    }
                }
            }
            if !docs.isEmpty {
                Section("Docs") {
                    ForEach(docs) { result in
                        resultRow(result)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .font(.callout)
            if let sub = result.subtitle {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func performSearch(_ q: String) async {
        isSearching = true
        error = nil
        do {
            results = try await MyrlinAPI.shared.searchSessions(query: q)
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}
