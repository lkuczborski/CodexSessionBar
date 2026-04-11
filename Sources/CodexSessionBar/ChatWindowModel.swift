import Foundation
import Observation

@MainActor
@Observable
final class ChatWindowModel {
    let route: ChatWindowRoute

    @ObservationIgnored
    private let client: CodexAppServerClient
    @ObservationIgnored
    private weak var owner: CodexMiniAppModel?
    @ObservationIgnored
    private var needsResumeBeforeTurn: Bool
    @ObservationIgnored
    private var hasRequestedModelCatalog = false
    private var draftAssistantID: String?
    private var draftAssistantText: String = ""

    private(set) var threadID: String?
    private(set) var summary: SessionSummary?
    private(set) var conversation: [ConversationEntry]
    private(set) var banner: SessionBanner?
    private(set) var availableModels: [CodexModel] = []
    private(set) var isLoadingModels: Bool = false
    private(set) var isSending: Bool = false
    var selectedModel: String? {
        didSet {
            ComposerPreferences.setSelectedModel(selectedModel)
            normalizeReasoningSelection()
        }
    }
    var selectedReasoningEffort: ReasoningEffortValue? {
        didSet {
            ComposerPreferences.setSelectedReasoningEffort(selectedReasoningEffort)
        }
    }
    var fastModeEnabled: Bool {
        didSet {
            ComposerPreferences.setFastModeEnabled(fastModeEnabled)
        }
    }
    var draftText: String = ""
    var workingDirectory: String

    init(
        route: ChatWindowRoute,
        initialSummary: SessionSummary?,
        initialRecord: SessionRecord?,
        fallbackWorkingDirectory: String,
        client: CodexAppServerClient,
        owner: CodexMiniAppModel
    ) {
        let resolvedThreadID = initialRecord?.summary.id ?? initialSummary?.id ?? route.threadID
        self.route = route
        self.client = client
        self.owner = owner
        self.threadID = resolvedThreadID
        self.summary = initialRecord?.summary ?? initialSummary
        self.conversation = initialRecord?.conversation ?? []
        self.workingDirectory = initialRecord?.summary.cwd.nonEmpty ?? initialSummary?.cwd.nonEmpty ?? fallbackWorkingDirectory
        self.needsResumeBeforeTurn = !(initialRecord?.summary.isLive ?? initialSummary?.isLive ?? false) && resolvedThreadID != nil
        self.selectedModel = ComposerPreferences.selectedModel
        self.selectedReasoningEffort = ComposerPreferences.selectedReasoningEffort
        self.fastModeEnabled = ComposerPreferences.fastModeEnabled

        if initialRecord == nil, let resolvedThreadID {
            Task { [weak self] in
                await self?.loadThread(threadID: resolvedThreadID)
            }
        }

        Task { [weak self] in
            await self?.loadComposerOptionsIfNeeded()
        }
    }

    var title: String {
        summary?.title ?? (threadID == nil ? "New mini session" : "Codex session")
    }

    var subtitle: String {
        summary?.workspaceLabel ?? workingDirectory
    }

    var statusBadgeLabel: String? {
        if let summary {
            return summary.statusBadgeLabel
        }

        return threadID == nil ? "Draft" : nil
    }

    var selectedCodexModel: CodexModel? {
        guard let selectedModel else {
            return nil
        }

        return availableModels.first(where: { $0.model == selectedModel })
    }

    var availableReasoningEfforts: [ReasoningEffortValue] {
        selectedCodexModel?.availableReasoningEfforts ?? []
    }

    var visibleConversation: [ConversationEntry] {
        guard let draftAssistantID else {
            return conversation
        }

        let streamingBody = draftAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Thinking…" : draftAssistantText
        return conversation + [
            ConversationEntry(
                id: draftAssistantID,
                kind: .assistant,
                title: "Codex",
                body: streamingBody,
                footnote: "Streaming",
                isStreaming: true
            )
        ]
    }

    func sendMessage() {
        let prompt = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else {
            return
        }

        let modelOverride = selectedModel
        let effortOverride = selectedReasoningEffort
        let serviceTierOverride: ServiceTierValue? = fastModeEnabled ? .fast : nil

        draftText = ""
        banner = nil
        conversation.append(
            ConversationEntry(
                id: "local-user-\(UUID().uuidString)",
                kind: .user,
                title: "You",
                body: prompt,
                footnote: nil,
                isStreaming: false
            )
        )
        isSending = true
        draftAssistantID = "stream-\(UUID().uuidString)"
        draftAssistantText = ""

        Task { [weak self] in
            await self?.performSend(
                prompt: prompt,
                model: modelOverride,
                effort: effortOverride,
                serviceTier: serviceTierOverride
            )
        }
    }

    func loadComposerOptionsIfNeeded() async {
        guard !hasRequestedModelCatalog else {
            return
        }

        hasRequestedModelCatalog = true
        await loadComposerOptions()
    }

    func updateWorkingDirectory(_ path: String) {
        workingDirectory = path.nonEmpty ?? workingDirectory
    }

    func replace(with record: SessionRecord) {
        threadID = record.summary.id
        summary = record.summary
        conversation = record.conversation
        workingDirectory = record.summary.cwd.nonEmpty ?? workingDirectory
        needsResumeBeforeTurn = !record.summary.isLive
        isSending = false
        draftAssistantID = nil
        draftAssistantText = ""
        owner?.bindWindowModel(self, to: record.summary.id)
    }

    func apply(latestSummary: SessionSummary?) {
        guard let latestSummary else {
            return
        }

        summary = latestSummary
        if let nonEmptyWorkspace = latestSummary.cwd.nonEmpty {
            workingDirectory = nonEmptyWorkspace
        }
        needsResumeBeforeTurn = !latestSummary.isLive
        owner?.bindWindowModel(self, to: latestSummary.id)
    }

    func handle(_ event: AppServerEvent) {
        switch event {
        case .turnStarted(let threadID, let turnID):
            guard threadID == self.threadID else {
                return
            }

            isSending = true
            if draftAssistantID == nil {
                draftAssistantID = "turn-\(turnID)"
                draftAssistantText = ""
            }

        case .agentMessageDelta(let threadID, _, let itemID, let delta):
            guard threadID == self.threadID else {
                return
            }

            draftAssistantID = itemID
            draftAssistantText.append(delta)

        case .turnCompleted(let threadID, _):
            guard threadID == self.threadID else {
                return
            }

            Task { [weak self] in
                await self?.loadThread(threadID: threadID)
            }

        case .serverNotice(let eventThreadID, let tone, let message):
            guard eventThreadID == nil || eventThreadID == self.threadID else {
                return
            }

            banner = SessionBanner(tone: tone, message: message)
            if tone == .failure {
                isSending = false
            }

        case .sessionsChanged, .error:
            break
        }
    }

    func refreshThreadContents() {
        guard let threadID else {
            return
        }

        Task { [weak self] in
            await self?.loadThread(threadID: threadID)
        }
    }

    private func performSend(
        prompt: String,
        model: String?,
        effort: ReasoningEffortValue?,
        serviceTier: ServiceTierValue?
    ) async {
        do {
            if threadID == nil {
                let summary = try await client.startThread(
                    cwd: workingDirectory,
                    model: model,
                    serviceTier: serviceTier
                )
                owner?.merge(summary: summary)
                threadID = summary.id
                self.summary = summary
                needsResumeBeforeTurn = false
                owner?.bindWindowModel(self, to: summary.id)
            } else if needsResumeBeforeTurn, let threadID {
                let record = try await client.resumeThread(
                    id: threadID,
                    cwd: workingDirectory,
                    model: model,
                    serviceTier: serviceTier
                )
                owner?.store(record: record)
                replace(with: record)
                needsResumeBeforeTurn = false
            }

            guard let threadID else {
                throw ClientError.disconnected
            }

            _ = try await client.startTurn(
                threadID: threadID,
                prompt: prompt,
                cwd: workingDirectory,
                model: model,
                effort: effort,
                serviceTier: serviceTier
            )
        } catch {
            banner = SessionBanner(tone: .failure, message: error.localizedDescription)
            isSending = false
            draftAssistantID = nil
            draftAssistantText = ""
        }
    }

    private func loadComposerOptions() async {
        guard !isLoadingModels else {
            return
        }

        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            availableModels = try await client.fetchModels()
            synchronizeSelectionsWithAvailableModels()
        } catch {
            if availableModels.isEmpty {
                hasRequestedModelCatalog = false
            }
        }
    }

    private func loadThread(threadID: String) async {
        do {
            let record = try await client.fetchThreadRecord(threadID: threadID)
            owner?.store(record: record)
        } catch {
            banner = SessionBanner(tone: .failure, message: error.localizedDescription)
            isSending = false
        }
    }

    private func normalizeReasoningSelection() {
        guard let selectedCodexModel else {
            return
        }

        guard let selectedReasoningEffort else {
            self.selectedReasoningEffort = selectedCodexModel.defaultReasoningEffort
            return
        }

        if !selectedCodexModel.availableReasoningEfforts.contains(selectedReasoningEffort) {
            self.selectedReasoningEffort = selectedCodexModel.defaultReasoningEffort
        }
    }

    private func synchronizeSelectionsWithAvailableModels() {
        guard !availableModels.isEmpty else {
            selectedModel = nil
            selectedReasoningEffort = nil
            return
        }

        if let selectedModel,
           availableModels.contains(where: { $0.model == selectedModel }) {
            normalizeReasoningSelection()
            return
        }

        let defaultModel = availableModels.first(where: \.isDefault) ?? availableModels[0]
        selectedModel = defaultModel.model
        selectedReasoningEffort = defaultModel.defaultReasoningEffort
    }
}
