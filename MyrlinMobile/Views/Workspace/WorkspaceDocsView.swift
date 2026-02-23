import SwiftUI

/// Viewer and editor for workspace documentation sections.
struct WorkspaceDocsView: View {
    let workspace: Workspace
    @State private var docs: WorkspaceDocs? = nil
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var isEditing = false
    @State private var editedDocs: WorkspaceDocs? = nil
    @State private var isSaving = false
    @State private var newGoal = ""
    @State private var newTask = ""

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading docs...")
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadDocs() } }
                }
            } else if let docs {
                if isEditing, let _ = editedDocs {
                    editForm(docs: Binding(
                        get: { editedDocs ?? docs },
                        set: { editedDocs = $0 }
                    ))
                } else {
                    docsList(docs: docs)
                }
            } else {
                ContentUnavailableView("No Docs",
                    systemImage: "doc.text",
                    description: Text("This workspace has no documentation yet."))
            }
        }
        .navigationTitle("Docs \u{2014} \(workspace.name)")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let _ = docs {
                    Button(isEditing ? "Done" : "Edit") {
                        if isEditing {
                            Task { await saveEdits() }
                        } else {
                            editedDocs = docs
                            isEditing = true
                        }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
        }
        .task { await loadDocs() }
        .refreshable { await loadDocs() }
    }

    // MARK: - Read-only list

    @ViewBuilder
    private func docsList(docs: WorkspaceDocs) -> some View {
        List {
            // Notes
            if let notes = docs.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    CollapsibleTextCard(label: "Notes", icon: "note.text", content: notes)
                }
            }

            // Goals
            if let goals = docs.goals, !goals.isEmpty {
                Section("Goals") {
                    ForEach(goals, id: \.self) { goal in
                        Label(goal, systemImage: "target")
                            .font(.body)
                    }
                }
            }

            // Tasks with checkboxes
            if let tasks = docs.tasks, !tasks.isEmpty {
                Section("Tasks") {
                    ForEach(tasks) { task in
                        HStack(spacing: 10) {
                            Button {
                                Task { await toggleTask(task) }
                            } label: {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.done ? .green : .secondary)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)

                            Text(task.text)
                                .strikethrough(task.done, color: .secondary)
                                .foregroundStyle(task.done ? .secondary : .primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Roadmap
            if let roadmap = docs.roadmap, !roadmap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    CollapsibleTextCard(label: "Roadmap", icon: "map", content: roadmap)
                }
            }

            // Rules
            if let rules = docs.rules, !rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    CollapsibleTextCard(label: "Rules", icon: "list.bullet.clipboard", content: rules)
                }
            }
        }
    }

    // MARK: - Edit form

    @ViewBuilder
    private func editForm(docs: Binding<WorkspaceDocs>) -> some View {
        List {
            // Notes
            Section("Notes") {
                TextEditor(text: Binding(
                    get: { docs.wrappedValue.notes ?? "" },
                    set: { docs.wrappedValue.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }

            // Goals
            Section("Goals") {
                ForEach(Array((docs.wrappedValue.goals ?? []).enumerated()), id: \.offset) { idx, goal in
                    HStack {
                        Text(goal)
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            docs.wrappedValue.goals?.remove(at: idx)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                HStack {
                    TextField("Add goal...", text: $newGoal)
                        .onSubmit { addGoal(docs: docs) }
                    Button("Add") { addGoal(docs: docs) }
                        .disabled(newGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Tasks
            Section("Tasks") {
                ForEach(Array((docs.wrappedValue.tasks ?? []).enumerated()), id: \.offset) { idx, task in
                    HStack {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.done ? .green : .secondary)
                        Text(task.text)
                            .strikethrough(task.done)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            docs.wrappedValue.tasks?.remove(at: idx)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                HStack {
                    TextField("Add task...", text: $newTask)
                        .onSubmit { addTask(docs: docs) }
                    Button("Add") { addTask(docs: docs) }
                        .disabled(newTask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Roadmap
            Section("Roadmap") {
                TextEditor(text: Binding(
                    get: { docs.wrappedValue.roadmap ?? "" },
                    set: { docs.wrappedValue.roadmap = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }

            // Rules
            Section("Rules") {
                TextEditor(text: Binding(
                    get: { docs.wrappedValue.rules ?? "" },
                    set: { docs.wrappedValue.rules = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 80)
            }
        }
    }

    private func addGoal(docs: Binding<WorkspaceDocs>) {
        let text = newGoal.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if docs.wrappedValue.goals == nil { docs.wrappedValue.goals = [] }
        docs.wrappedValue.goals?.append(text)
        newGoal = ""
    }

    private func addTask(docs: Binding<WorkspaceDocs>) {
        let text = newTask.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if docs.wrappedValue.tasks == nil { docs.wrappedValue.tasks = [] }
        let idx = docs.wrappedValue.tasks?.count ?? 0
        docs.wrappedValue.tasks?.append(WorkspaceTask(index: idx, text: text, done: false))
        newTask = ""
    }

    // MARK: - Network

    private func loadDocs() async {
        isLoading = true
        error = nil
        do {
            var fetched = try await MyrlinAPI.shared.getWorkspaceDocs(workspace.id)
            // Re-assign positional indices (server may not include index field)
            if let tasks = fetched.tasks {
                fetched.tasks = tasks.enumerated().map { i, t in
                    WorkspaceTask(index: i, text: t.text, done: t.done)
                }
            }
            docs = fetched
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleTask(_ task: WorkspaceTask) async {
        do {
            try await MyrlinAPI.shared.toggleWorkspaceTask(workspace.id, index: task.index)
            // Optimistic update
            if var tasks = docs?.tasks,
               let idx = tasks.firstIndex(where: { $0.index == task.index }) {
                tasks[idx] = WorkspaceTask(index: task.index, text: task.text, done: !task.done)
                docs?.tasks = tasks
            }
        } catch {
            // Reload on failure
            await loadDocs()
        }
    }

    private func saveEdits() async {
        guard let edited = editedDocs else { isEditing = false; return }
        isSaving = true
        do {
            let saved = try await MyrlinAPI.shared.updateWorkspaceDocs(workspace.id, docs: edited)
            docs = saved
            isEditing = false
        } catch {
            // Rollback
            editedDocs = docs
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Collapsible Text Card

private struct CollapsibleTextCard: View {
    let label: String
    let icon: String
    let content: String
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label(label, systemImage: icon)
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.vertical, 4)
                if let attributed = try? AttributedString(markdown: content) {
                    Text(attributed)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
