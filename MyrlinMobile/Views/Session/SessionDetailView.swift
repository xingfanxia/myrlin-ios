import SwiftUI
import UIKit

/// Sheet showing session metadata, cost, and actions (restart, stop, delete).
struct SessionDetailView: View {
    let session: Session
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var editedName: String = ""
    @State private var cost: SessionCost? = nil
    @State private var isLoadingCost = false
    @State private var costError: String? = nil
    @State private var isSavingName = false
    @State private var isRestarting = false
    @State private var isStopping = false
    @State private var showDeleteConfirm = false
    @State private var actionError: String? = nil

    // Tags editing
    @State private var editableTags: [String] = []
    @State private var newTag = ""
    @State private var isSavingTags = false

    // AI Actions
    @State private var autoTitleResult: String? = nil
    @State private var isAutoTitling = false
    @State private var summaryResult: String? = nil
    @State private var isShowingSummary = false
    @State private var isSummarizing = false
    @State private var tasksList: [String] = []
    @State private var isShowingTasks = false
    @State private var isExtractingTasks = false
    @State private var exportContext: String? = nil
    @State private var isExportingContext = false
    @State private var aiActionError: String? = nil

    // Subagents
    @State private var subagentsList: [SubagentInfo] = []
    @State private var isLoadingSubagents = false
    @State private var subagentsLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                // Name section (editable inline)
                Section("Name") {
                    HStack {
                        TextField("Session name", text: $editedName)
                            .autocorrectionDisabled()
                        if isSavingName {
                            ProgressView().scaleEffect(0.7)
                        } else if editedName != session.name {
                            Button("Save") { Task { await saveName() } }
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Info section
                Section("Details") {
                    if let dir = session.workingDir {
                        LabeledContent("Working Dir") {
                            Text((dir as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contextMenu {
                            Button("Copy Path") { UIPasteboard.general.string = dir }
                        }
                    }
                    LabeledContent("Status") {
                        StatusBadge(status: session.status)
                    }
                    if let model = session.model {
                        LabeledContent("Model", value: model)
                    }
                    if let created = session.createdAt {
                        LabeledContent("Created") {
                            Text(created.formatted(.relative(presentation: .named)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let lastActive = session.lastActive {
                        LabeledContent("Last Active") {
                            Text(lastActive.formatted(.relative(presentation: .named)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let claudeId = session.claudeSessionId {
                        LabeledContent("Claude ID") {
                            Text(claudeId)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                // Tags section (editable)
                Section("Tags") {
                    ForEach(editableTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                                .font(.callout)
                            Spacer()
                            Button {
                                editableTags.removeAll { $0 == tag }
                                Task { await saveTags() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        TextField("Add tag...", text: $newTag)
                            .autocorrectionDisabled()
                            .onSubmit { addTag() }
                        Button("Add") { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        if isSavingTags { ProgressView().scaleEffect(0.7) }
                    }
                }

                // Cost section
                Section("Usage & Cost") {
                    if isLoadingCost {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if let cost {
                        if let total = cost.totalTokens {
                            LabeledContent("Total Tokens", value: total.formatted())
                        }
                        if let input = cost.inputTokens {
                            LabeledContent("Input Tokens", value: input.formatted())
                        }
                        if let output = cost.outputTokens {
                            LabeledContent("Output Tokens", value: output.formatted())
                        }
                        if let usd = cost.estimatedCost {
                            LabeledContent("Estimated Cost") {
                                Text(usd, format: .currency(code: "USD"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let err = costError {
                        Text(err).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Load Cost") { Task { await loadCost() } }
                    }
                }

                // AI Actions
                Section("AI Actions") {
                    if let err = aiActionError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    // Auto-title
                    Button {
                        Task { await runAutoTitle() }
                    } label: {
                        HStack {
                            Label("Auto-Title", systemImage: "wand.and.stars")
                            Spacer()
                            if isAutoTitling { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isAutoTitling || isSummarizing || isExtractingTasks || isExportingContext)

                    // Summarize
                    Button {
                        Task { await runSummarize() }
                    } label: {
                        HStack {
                            Label("Summarize Session", systemImage: "text.alignleft")
                            Spacer()
                            if isSummarizing { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isAutoTitling || isSummarizing || isExtractingTasks || isExportingContext)

                    // Extract tasks
                    Button {
                        Task { await runExtractTasks() }
                    } label: {
                        HStack {
                            Label("Extract Tasks", systemImage: "checklist")
                            Spacer()
                            if isExtractingTasks { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isAutoTitling || isSummarizing || isExtractingTasks || isExportingContext)

                    // Export context
                    Button {
                        Task { await runExportContext() }
                    } label: {
                        HStack {
                            Label("Export Context", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isExportingContext { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isAutoTitling || isSummarizing || isExtractingTasks || isExportingContext)
                }

                // Subagents
                if subagentsLoaded && !subagentsList.isEmpty {
                    Section("Subagents") {
                        ForEach(subagentsList) { agent in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(agent.status == "running" ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.type ?? "Agent")
                                        .font(.callout)
                                    if let desc = agent.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                // Actions
                Section("Actions") {
                    if let err = actionError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    Button {
                        Task { await restart() }
                    } label: {
                        HStack {
                            Label("Restart Session", systemImage: "arrow.counterclockwise")
                            Spacer()
                            if isRestarting { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(isRestarting || isStopping)

                    if session.status == .running {
                        Button {
                            Task { await stop() }
                        } label: {
                            HStack {
                                Label("Stop Session", systemImage: "stop.circle")
                                Spacer()
                                if isStopping { ProgressView().scaleEffect(0.7) }
                            }
                        }
                        .disabled(isRestarting || isStopping)
                    }
                }

                // Destructive
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                editedName = session.name
                editableTags = session.tags ?? []
                Task { await loadCost() }
                Task { await loadSubagents() }
            }
            .confirmationDialog("Delete this session?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteSession() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(isPresented: $isShowingSummary) {
                NavigationStack {
                    ScrollView {
                        Text(summaryResult ?? "")
                            .padding()
                            .textSelection(.enabled)
                    }
                    .navigationTitle("Summary")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSummary = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingTasks) {
                NavigationStack {
                    List(tasksList, id: \.self) { task in
                        Text(task)
                    }
                    .navigationTitle("Extracted Tasks")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingTasks = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveName() async {
        isSavingName = true
        defer { isSavingName = false }
        do {
            let updated = try await MyrlinAPI.shared.updateSession(session.id, name: editedName)
            if let idx = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                appState.sessions[idx] = updated
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadCost() async {
        isLoadingCost = true
        costError = nil
        do {
            cost = try await MyrlinAPI.shared.sessionCost(session.id)
        } catch {
            costError = "Cost unavailable"
        }
        isLoadingCost = false
    }

    private func restart() async {
        isRestarting = true
        defer { isRestarting = false }
        do {
            try await MyrlinAPI.shared.restartSession(session.id)
            await appState.refreshSessions()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func stop() async {
        isStopping = true
        defer { isStopping = false }
        do {
            try await MyrlinAPI.shared.stopSession(session.id)
            await appState.refreshSessions()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteSession() async {
        do {
            try await MyrlinAPI.shared.deleteSession(session.id)
            appState.sessions.removeAll { $0.id == session.id }
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !editableTags.contains(tag) else { return }
        editableTags.append(tag)
        newTag = ""
        Task { await saveTags() }
    }

    private func saveTags() async {
        isSavingTags = true
        defer { isSavingTags = false }
        do {
            let updated = try await MyrlinAPI.shared.updateSession(session.id, tags: editableTags)
            if let idx = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                appState.sessions[idx] = updated
            }
        } catch {
            aiActionError = error.localizedDescription
        }
    }

    private func runAutoTitle() async {
        isAutoTitling = true
        aiActionError = nil
        defer { isAutoTitling = false }
        do {
            let newName = try await MyrlinAPI.shared.autoTitle(session.id)
            editedName = newName
            if let idx = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                appState.sessions[idx].name = newName
            }
        } catch {
            aiActionError = error.localizedDescription
        }
    }

    private func runSummarize() async {
        isSummarizing = true
        aiActionError = nil
        defer { isSummarizing = false }
        do {
            summaryResult = try await MyrlinAPI.shared.summarizeSession(session.id)
            isShowingSummary = true
        } catch {
            aiActionError = error.localizedDescription
        }
    }

    private func runExtractTasks() async {
        isExtractingTasks = true
        aiActionError = nil
        defer { isExtractingTasks = false }
        do {
            tasksList = try await MyrlinAPI.shared.extractTasks(session.id)
            isShowingTasks = true
        } catch {
            aiActionError = error.localizedDescription
        }
    }

    private func runExportContext() async {
        isExportingContext = true
        aiActionError = nil
        defer { isExportingContext = false }
        do {
            let ctx = try await MyrlinAPI.shared.exportContext(session.id)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first,
               let vc = window.rootViewController {
                let av = UIActivityViewController(activityItems: [ctx], applicationActivities: nil)
                vc.present(av, animated: true)
            }
        } catch {
            aiActionError = error.localizedDescription
        }
    }

    private func loadSubagents() async {
        guard !subagentsLoaded else { return }
        isLoadingSubagents = true
        defer { isLoadingSubagents = false }
        do {
            subagentsList = try await MyrlinAPI.shared.subagents(session.id)
            subagentsLoaded = true
        } catch {
            // 404 = no subagents endpoint, just hide the section
            subagentsLoaded = true
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: Session.SessionStatus

    private var color: Color {
        switch status {
        case .running: return .green
        case .stopped: return .gray
        case .error: return .red
        case .unknown: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.rawValue.capitalized)
                .foregroundStyle(.secondary)
        }
    }
}
