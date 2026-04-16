import Foundation

struct SessionSummary: Identifiable, Hashable, Sendable {
    let id: String
    let name: String?
    let preview: String
    let cwd: String
    let path: String?
    let modelProvider: String
    let source: SessionSourceKind
    let createdAt: Date
    let updatedAt: Date
    let status: ThreadStatus
    let isEphemeral: Bool
    let agentNickname: String?
    let agentRole: String?
    let gitBranch: String?

    var title: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreview.isEmpty {
            return trimmedPreview
        }

        if let agentNickname, !agentNickname.isEmpty {
            return agentNickname
        }

        return "Untitled session"
    }

    var previewText: String {
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPreview.isEmpty ? "No prompt preview available yet." : trimmedPreview
    }

    var statusBadgeLabel: String? {
        status.badgeLabel
    }

    var sourceLabel: String {
        source.displayLabel
    }

    var updatedRelative: String {
        RelativeDateTimeFormatter.makeCodexFormatter().localizedString(for: updatedAt, relativeTo: Date())
    }

    var createdRelative: String {
        RelativeDateTimeFormatter.makeCodexFormatter().localizedString(for: createdAt, relativeTo: Date())
    }

    var isLive: Bool {
        status.isLoaded
    }

    var workspaceLabel: String {
        cwd.isEmpty ? "Home" : cwd
    }

    func matches(searchQuery: String) -> Bool {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        let searchFields = [
            id,
            title,
            previewText,
            workspaceLabel,
            sourceLabel,
            modelProvider,
            gitBranch,
            agentNickname,
            agentRole
        ]

        return searchFields
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }
}

struct SessionRecord: Equatable, Sendable {
    var summary: SessionSummary
    var conversation: [ConversationEntry]
}

struct ConversationEntry: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case user
        case assistant
        case plan
        case tool
        case notice
    }

    let id: String
    let kind: Kind
    let title: String
    let body: String
    let footnote: String?
    let isStreaming: Bool

    var defaultTranscriptCollapsed: Bool {
        canCollapseInTranscript
    }

    var canCollapseInTranscript: Bool {
        kind == .tool && !isStreaming && transcriptLineCount > 2
    }

    var copyPayload: String {
        ([showsTranscriptTitle ? title : nil, body.nonEmpty, footnote?.nonEmpty]
            .compactMap { $0 }
            .joined(separator: "\n\n"))
            .nonEmpty ?? body
    }

    func matches(searchQuery: String) -> Bool {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return true
        }

        return [title, body, footnote]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    var transcriptPreview: String {
        body
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmedForPreview(maxLength: 180)
    }

    private var transcriptLineCount: Int {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else {
            return 0
        }

        return normalizedBody.components(separatedBy: .newlines).count
    }

    var showsTranscriptTitle: Bool {
        switch kind {
        case .user, .assistant:
            false
        case .plan, .tool, .notice:
            true
        }
    }
}

struct SessionBanner: Identifiable, Equatable, Sendable {
    enum Tone: String, Equatable, Sendable {
        case info
        case warning
        case failure
    }

    let id: UUID = UUID()
    let tone: Tone
    let message: String
}

struct ChatWindowRoute: Hashable, Codable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static func draft() -> ChatWindowRoute {
        ChatWindowRoute(rawValue: "draft:\(UUID().uuidString)")
    }

    static func thread(_ id: String) -> ChatWindowRoute {
        ChatWindowRoute(rawValue: "thread:\(id)")
    }

    var id: String {
        rawValue
    }

    var threadID: String? {
        guard rawValue.hasPrefix("thread:") else {
            return nil
        }

        return String(rawValue.dropFirst("thread:".count))
    }
}

struct ThreadListResponse: Decodable, Sendable {
    let data: [CodexThread]
    let nextCursor: String?
}

struct ThreadReadResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct ThreadStartResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct ThreadResumeResponse: Decodable, Sendable {
    let thread: CodexThread
}

struct TurnStartResponse: Decodable, Sendable {
    let turn: CodexTurn
}

struct ModelListResponse: Decodable, Sendable {
    let data: [CodexModel]
    let nextCursor: String?
}

struct CodexModel: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let hidden: Bool
    let isDefault: Bool
    let defaultReasoningEffort: ReasoningEffortValue
    let supportedReasoningEfforts: [ReasoningEffortOption]

    var availableReasoningEfforts: [ReasoningEffortValue] {
        let values = supportedReasoningEfforts.map(\.reasoningEffort)
        return values.isEmpty ? [defaultReasoningEffort] : values
    }
}

struct ReasoningEffortOption: Decodable, Equatable, Sendable {
    let description: String
    let reasoningEffort: ReasoningEffortValue
}

enum ReasoningEffortValue: String, CaseIterable, Codable, Equatable, Sendable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var label: String {
        switch self {
        case .none: "None"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Extra High"
        }
    }
}

enum ServiceTierValue: String, CaseIterable, Codable, Equatable, Sendable {
    case fast
    case flex

    var label: String {
        switch self {
        case .fast: "Fast"
        case .flex: "Flex"
        }
    }
}

struct GitInfo: Decodable, Hashable, Sendable {
    let sha: String?
    let branch: String?
    let originUrl: String?
}

struct CodexThread: Decodable, Sendable {
    let id: String
    let preview: String
    let ephemeral: Bool
    let modelProvider: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
    let status: ThreadStatus
    let path: String?
    let cwd: String
    let cliVersion: String?
    let source: SessionSourceKind
    let agentNickname: String?
    let agentRole: String?
    let gitInfo: GitInfo?
    let name: String?
    let turns: [CodexTurn]

    init(
        id: String,
        preview: String,
        ephemeral: Bool,
        modelProvider: String,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        status: ThreadStatus,
        path: String?,
        cwd: String,
        cliVersion: String?,
        source: SessionSourceKind,
        agentNickname: String?,
        agentRole: String?,
        gitInfo: GitInfo?,
        name: String?,
        turns: [CodexTurn]
    ) {
        self.id = id
        self.preview = preview
        self.ephemeral = ephemeral
        self.modelProvider = modelProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.path = path
        self.cwd = cwd
        self.cliVersion = cliVersion
        self.source = source
        self.agentNickname = agentNickname
        self.agentRole = agentRole
        self.gitInfo = gitInfo
        self.name = name
        self.turns = turns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        preview = (try? container.decode(String.self, forKey: .preview)) ?? ""
        ephemeral = (try? container.decode(Bool.self, forKey: .ephemeral)) ?? false
        modelProvider = (try? container.decode(String.self, forKey: .modelProvider)) ?? ""
        createdAt = (try? container.decode(TimeInterval.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? container.decode(TimeInterval.self, forKey: .updatedAt)) ?? 0
        status = (try? container.decode(ThreadStatus.self, forKey: .status)) ?? .notLoaded
        path = try? container.decodeIfPresent(String.self, forKey: .path)
        cwd = (try? container.decode(String.self, forKey: .cwd)) ?? ""
        cliVersion = try? container.decodeIfPresent(String.self, forKey: .cliVersion)
        source = (try? container.decode(SessionSourceKind.self, forKey: .source)) ?? .unknown
        agentNickname = try? container.decodeIfPresent(String.self, forKey: .agentNickname)
        agentRole = try? container.decodeIfPresent(String.self, forKey: .agentRole)
        gitInfo = try? container.decodeIfPresent(GitInfo.self, forKey: .gitInfo)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        turns = (try? container.decode(LossyArray<CodexTurn>.self, forKey: .turns).elements) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case preview
        case ephemeral
        case modelProvider
        case createdAt
        case updatedAt
        case status
        case path
        case cwd
        case cliVersion
        case source
        case agentNickname
        case agentRole
        case gitInfo
        case name
        case turns
    }
}

struct CodexTurn: Decodable, Hashable, Sendable {
    let id: String
    let items: [ThreadItem]
    let status: TurnStatusValue
    let error: TurnErrorInfo?

    init(id: String, items: [ThreadItem], status: TurnStatusValue, error: TurnErrorInfo?) {
        self.id = id
        self.items = items
        self.status = status
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        items = (try? container.decode(LossyArray<ThreadItem>.self, forKey: .items).elements) ?? []
        status = (try? container.decode(TurnStatusValue.self, forKey: .status)) ?? .completed
        error = try? container.decodeIfPresent(TurnErrorInfo.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case items
        case status
        case error
    }
}

enum TurnStatusValue: String, Decodable, Hashable, Sendable {
    case completed
    case interrupted
    case failed
    case inProgress
}

struct TurnErrorInfo: Decodable, Hashable, Sendable {
    let message: String
    let additionalDetails: String?
}

enum ThreadItem: Hashable, Sendable {
    case userMessage(ThreadUserMessageItem)
    case agentMessage(ThreadAgentMessageItem)
    case plan(ThreadPlanItem)
    case reasoning(ThreadReasoningItem)
    case commandExecution(ThreadCommandExecutionItem)
    case fileChange(ThreadFileChangeItem)
    case mcpToolCall(ThreadMcpToolCallItem)
    case dynamicToolCall(ThreadDynamicToolCallItem)
    case collabAgentToolCall(ThreadCollabAgentToolCallItem)
    case webSearch(ThreadWebSearchItem)
    case imageView(ThreadImageViewItem)
    case imageGeneration(ThreadImageGenerationItem)
    case note(ThreadNoteItem)
    case unknown(id: String, type: String)

    var id: String {
        switch self {
        case .userMessage(let item): item.id
        case .agentMessage(let item): item.id
        case .plan(let item): item.id
        case .reasoning(let item): item.id
        case .commandExecution(let item): item.id
        case .fileChange(let item): item.id
        case .mcpToolCall(let item): item.id
        case .dynamicToolCall(let item): item.id
        case .collabAgentToolCall(let item): item.id
        case .webSearch(let item): item.id
        case .imageView(let item): item.id
        case .imageGeneration(let item): item.id
        case .note(let item): item.id
        case .unknown(let id, _): id
        }
    }
}

extension ThreadItem: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"

        switch type {
        case "userMessage":
            self = .userMessage(try ThreadUserMessageItem(from: decoder))
        case "agentMessage":
            self = .agentMessage(try ThreadAgentMessageItem(from: decoder))
        case "plan":
            self = .plan(try ThreadPlanItem(from: decoder))
        case "reasoning":
            self = .reasoning(try ThreadReasoningItem(from: decoder))
        case "commandExecution":
            self = .commandExecution(try ThreadCommandExecutionItem(from: decoder))
        case "fileChange":
            self = .fileChange(try ThreadFileChangeItem(from: decoder))
        case "mcpToolCall":
            self = .mcpToolCall(try ThreadMcpToolCallItem(from: decoder))
        case "dynamicToolCall":
            self = .dynamicToolCall(try ThreadDynamicToolCallItem(from: decoder))
        case "collabAgentToolCall":
            self = .collabAgentToolCall(try ThreadCollabAgentToolCallItem(from: decoder))
        case "webSearch":
            self = .webSearch(try ThreadWebSearchItem(from: decoder))
        case "imageView":
            self = .imageView(try ThreadImageViewItem(from: decoder))
        case "imageGeneration":
            self = .imageGeneration(try ThreadImageGenerationItem(from: decoder))
        case "hookPrompt",
             "enteredReviewMode",
             "exitedReviewMode",
             "contextCompaction":
            self = .note(try ThreadNoteItem(from: decoder))
        default:
            let id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
            self = .unknown(id: id, type: type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
    }
}

struct ThreadUserMessageItem: Decodable, Hashable, Sendable {
    let id: String
    let content: [UserInputPayload]
}

struct ThreadAgentMessageItem: Decodable, Hashable, Sendable {
    let id: String
    let text: String
}

struct ThreadPlanItem: Decodable, Hashable, Sendable {
    let id: String
    let text: String
}

struct ThreadReasoningItem: Decodable, Hashable, Sendable {
    let id: String
    let summary: [String]
    let content: [String]
}

struct ThreadCommandExecutionItem: Decodable, Hashable, Sendable {
    let id: String
    let command: String
    let cwd: String
    let status: CommandExecutionStatusValue
    let aggregatedOutput: String?
    let exitCode: Int?
}

struct ThreadFileChangeItem: Decodable, Hashable, Sendable {
    let id: String
    let changes: [FileUpdateChange]
    let status: PatchApplyStatusValue
}

struct ThreadMcpToolCallItem: Decodable, Hashable, Sendable {
    let id: String
    let server: String
    let tool: String
    let status: ToolProgressStatus
}

struct ThreadDynamicToolCallItem: Decodable, Hashable, Sendable {
    let id: String
    let tool: String
    let status: ToolProgressStatus
    let contentItems: [DynamicToolOutputContentItem]?
    let success: Bool?
}

struct ThreadCollabAgentToolCallItem: Decodable, Hashable, Sendable {
    let id: String
    let tool: String
    let status: ToolProgressStatus
    let prompt: String?
}

struct ThreadWebSearchItem: Decodable, Hashable, Sendable {
    let id: String
    let query: String
}

struct ThreadImageViewItem: Decodable, Hashable, Sendable {
    let id: String
    let path: String
}

struct ThreadImageGenerationItem: Decodable, Hashable, Sendable {
    let id: String
    let status: String
    let result: String
    let savedPath: String?
}

struct ThreadNoteItem: Decodable, Hashable, Sendable {
    let id: String
    let type: String
    let review: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = (try? container.decode(String.self, forKey: .type)) ?? "note"
        review = try? container.decodeIfPresent(String.self, forKey: .review)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case review
    }
}

struct FileUpdateChange: Decodable, Hashable, Sendable {
    let path: String
    let kind: String
    let diff: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = (try? container.decode(String.self, forKey: .path)) ?? ""
        diff = (try? container.decode(String.self, forKey: .diff)) ?? ""

        if let rawKind = try? container.decode(String.self, forKey: .kind) {
            kind = rawKind
            return
        }

        if let kindContainer = try? container.nestedContainer(keyedBy: KindCodingKeys.self, forKey: .kind),
           let type = try? kindContainer.decode(String.self, forKey: .type) {
            kind = type
            return
        }

        kind = "unknown"
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case kind
        case diff
    }

    private enum KindCodingKeys: String, CodingKey {
        case type
    }
}

private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []

        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(DiscardedDecodableValue.self)
            }
        }

        self.elements = elements
    }
}

private struct DiscardedDecodableValue: Decodable {
    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            while !container.isAtEnd {
                _ = try? container.decode(DiscardedDecodableValue.self)
            }
            return
        }

        if let container = try? decoder.container(keyedBy: LossyCodingKey.self) {
            for key in container.allKeys {
                _ = try? container.decode(DiscardedDecodableValue.self, forKey: key)
            }
            return
        }

        _ = try? decoder.singleValueContainer()
    }
}

private struct LossyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

enum CommandExecutionStatusValue: String, Decodable, Hashable, Sendable {
    case inProgress
    case completed
    case failed
    case declined

    var displayLabel: String {
        switch self {
        case .inProgress: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .declined: "Declined"
        }
    }
}

enum PatchApplyStatusValue: String, Decodable, Hashable, Sendable {
    case inProgress
    case completed
    case failed
    case declined
}

enum ToolProgressStatus: String, Decodable, Hashable, Sendable {
    case inProgress
    case completed
    case failed
}

enum DynamicToolOutputContentItem: Decodable, Hashable, Sendable {
    case inputText(String)
    case inputImage(String)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"

        switch type {
        case "inputText":
            self = .inputText((try? container.decode(String.self, forKey: .text)) ?? "")
        case "inputImage":
            self = .inputImage((try? container.decode(String.self, forKey: .imageUrl)) ?? "")
        default:
            self = .unknown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl
    }
}

enum UserInputPayload: Hashable, Sendable {
    case text(String)
    case image(URL)
    case localImage(String)
    case skill(name: String)
    case mention(name: String)
    case unknown
}

extension UserInputPayload: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"

        switch type {
        case "text":
            self = .text((try? container.decode(String.self, forKey: .text)) ?? "")
        case "image":
            if let urlString = try? container.decode(String.self, forKey: .url), let url = URL(string: urlString) {
                self = .image(url)
            } else {
                self = .unknown
            }
        case "localImage":
            self = .localImage((try? container.decode(String.self, forKey: .path)) ?? "")
        case "skill":
            self = .skill(name: (try? container.decode(String.self, forKey: .name)) ?? "")
        case "mention":
            self = .mention(name: (try? container.decode(String.self, forKey: .name)) ?? "")
        default:
            self = .unknown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case url
        case path
        case name
    }
}

enum SessionSourceKind: Hashable, Sendable {
    case cli
    case vscode
    case exec
    case appServer
    case custom(String)
    case subAgent(SubAgentSourceKind)
    case unknown

    static var threadListFilterValues: [SessionSourceKind] {
        [
            .cli,
            .vscode,
            .exec,
            .appServer,
            .subAgent(.generic),
            .subAgent(.review),
            .subAgent(.compact),
            .subAgent(.threadSpawn),
            .subAgent(.other("other"))
        ]
    }

    var displayLabel: String {
        switch self {
        case .cli: "CLI"
        case .vscode: "VS Code"
        case .exec: "Exec"
        case .appServer: "App Server"
        case .custom(let label): label
        case .subAgent(let kind): kind.displayLabel
        case .unknown: "Unknown"
        }
    }
}

extension SessionSourceKind: Decodable {
    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let rawValue = try? singleValueContainer.decode(String.self) {
            switch rawValue {
            case "cli": self = .cli
            case "vscode": self = .vscode
            case "exec": self = .exec
            case "appServer": self = .appServer
            case "unknown": self = .unknown
            default: self = .custom(rawValue)
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let custom = try? container.decode(String.self, forKey: .custom) {
            self = .custom(custom)
            return
        }

        if let subAgent = try? container.decode(SubAgentSourceKind.self, forKey: .subAgent) {
            self = .subAgent(subAgent)
            return
        }

        self = .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case custom
        case subAgent
    }
}

extension SessionSourceKind: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .cli:
            try container.encode("cli")
        case .vscode:
            try container.encode("vscode")
        case .exec:
            try container.encode("exec")
        case .appServer:
            try container.encode("appServer")
        case .custom:
            try container.encode("unknown")
        case .subAgent(let kind):
            switch kind {
            case .generic:
                try container.encode("subAgent")
            case .review:
                try container.encode("subAgentReview")
            case .compact:
                try container.encode("subAgentCompact")
            case .threadSpawn:
                try container.encode("subAgentThreadSpawn")
            case .memoryConsolidation, .other:
                try container.encode("subAgentOther")
            }
        case .unknown:
            try container.encode("unknown")
        }
    }
}

enum SubAgentSourceKind: Hashable, Sendable {
    case generic
    case review
    case compact
    case threadSpawn
    case memoryConsolidation
    case other(String)

    var displayLabel: String {
        switch self {
        case .generic: "Sub-agent"
        case .review: "Review agent"
        case .compact: "Compact agent"
        case .threadSpawn: "Spawned agent"
        case .memoryConsolidation: "Memory agent"
        case .other(let label): label
        }
    }
}

extension SubAgentSourceKind: Decodable {
    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let rawValue = try? singleValueContainer.decode(String.self) {
            switch rawValue {
            case "review": self = .review
            case "compact": self = .compact
            case "memory_consolidation": self = .memoryConsolidation
            default: self = .generic
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decode(ThreadSpawnPayload.self, forKey: .threadSpawn)) != nil {
            self = .threadSpawn
            return
        }

        if let other = try? container.decode(String.self, forKey: .other) {
            self = .other(other)
            return
        }

        self = .generic
    }

    private struct ThreadSpawnPayload: Decodable, Hashable, Sendable {
        let parentThreadId: String?
        let depth: Int?
        let agentNickname: String?
        let agentRole: String?
    }

    private enum CodingKeys: String, CodingKey {
        case threadSpawn = "thread_spawn"
        case other
    }
}

enum ThreadActiveFlag: String, Decodable, Hashable, Sendable {
    case waitingOnApproval
    case waitingOnUserInput
}

enum ThreadStatus: Hashable, Sendable {
    case notLoaded
    case idle
    case systemError
    case active(flags: [ThreadActiveFlag])
    case unknown

    var isLoaded: Bool {
        switch self {
        case .notLoaded:
            false
        case .idle, .systemError, .active, .unknown:
            true
        }
    }

    var badgeLabel: String? {
        switch self {
        case .notLoaded:
            return nil
        case .idle:
            return "Idle"
        case .systemError:
            return "System error"
        case .active(let flags):
            if flags.isEmpty {
                return "Active"
            }

            let labels = flags.map { flag in
                switch flag {
                case .waitingOnApproval:
                    "Waiting on approval"
                case .waitingOnUserInput:
                    "Waiting on input"
                }
            }
            return labels.joined(separator: " • ")
        case .unknown:
            return "Live"
        }
    }
}

extension ThreadStatus: Decodable {
    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let rawValue = try? singleValueContainer.decode(String.self) {
            switch rawValue {
            case "notLoaded": self = .notLoaded
            case "idle": self = .idle
            case "systemError": self = .systemError
            case "active": self = .active(flags: [])
            default: self = .unknown
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"

        switch type {
        case "notLoaded":
            self = .notLoaded
        case "idle":
            self = .idle
        case "systemError":
            self = .systemError
        case "active":
            self = .active(flags: (try? container.decode([ThreadActiveFlag].self, forKey: .activeFlags)) ?? [])
        default:
            self = .unknown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }
}

extension CodexThread {
    var sessionSummary: SessionSummary {
        SessionSummary(
            id: id,
            name: name,
            preview: preview,
            cwd: cwd,
            path: path,
            modelProvider: modelProvider,
            source: source,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            status: status,
            isEphemeral: ephemeral,
            agentNickname: agentNickname,
            agentRole: agentRole,
            gitBranch: gitInfo?.branch
        )
    }

    var sessionRecord: SessionRecord {
        SessionRecord(summary: sessionSummary, conversation: turns.flatMap(\.conversationEntries))
    }
}

extension CodexTurn {
    var conversationEntries: [ConversationEntry] {
        var entries: [ConversationEntry] = []

        for item in items {
            switch item {
            case .userMessage(let message):
                let body = message.content.conversationText
                guard !body.isEmpty else {
                    continue
                }

                entries.append(
                    ConversationEntry(
                        id: message.id,
                        kind: .user,
                        title: "You",
                        body: body,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .agentMessage(let message):
                guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }

                entries.append(
                    ConversationEntry(
                        id: message.id,
                        kind: .assistant,
                        title: "Codex",
                        body: message.text,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .plan(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .plan,
                        title: "Plan",
                        body: item.text,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .reasoning(let item):
                let body = (item.summary + item.content)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")

                guard !body.isEmpty else {
                    continue
                }

                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .notice,
                        title: "Reasoning summary",
                        body: body,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .commandExecution(let item):
                let body = item.aggregatedOutput?.trimmedForPreview(maxLength: 600) ?? item.command
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "$ \(item.command)",
                        body: body,
                        footnote: "\(item.status.displayLabel) • \(item.cwd)",
                        isStreaming: false
                    )
                )

            case .fileChange(let item):
                let paths = item.changes.map(\.path)
                let body = paths.prefix(4).joined(separator: "\n")
                let summary = body.isEmpty ? "Touched \(item.changes.count) file(s)." : body
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "File changes",
                        body: summary,
                        footnote: "\(item.status.rawValue) • \(item.changes.count) file(s)",
                        isStreaming: false
                    )
                )

            case .mcpToolCall(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "\(item.server)/\(item.tool)",
                        body: "MCP tool call",
                        footnote: item.status.rawValue,
                        isStreaming: false
                    )
                )

            case .dynamicToolCall(let item):
                let body = item.contentItems?.compactMap { contentItem in
                    switch contentItem {
                    case .inputText(let text):
                        text
                    case .inputImage(let imageURL):
                        imageURL
                    case .unknown:
                        nil
                    }
                }
                .joined(separator: "\n")

                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: item.tool,
                        body: body?.trimmedForPreview(maxLength: 600) ?? "Dynamic tool call",
                        footnote: item.status.rawValue,
                        isStreaming: false
                    )
                )

            case .collabAgentToolCall(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: item.tool,
                        body: item.prompt?.trimmedForPreview(maxLength: 400) ?? "Collaboration agent call",
                        footnote: item.status.rawValue,
                        isStreaming: false
                    )
                )

            case .webSearch(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "Web search",
                        body: item.query,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .imageView(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "Viewed image",
                        body: item.path,
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .imageGeneration(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .tool,
                        title: "Generated image",
                        body: item.savedPath ?? item.result,
                        footnote: item.status,
                        isStreaming: false
                    )
                )

            case .note(let item):
                entries.append(
                    ConversationEntry(
                        id: item.id,
                        kind: .notice,
                        title: item.type.humanizedProtocolLabel,
                        body: item.review ?? "Session state updated.",
                        footnote: nil,
                        isStreaming: false
                    )
                )

            case .unknown:
                continue
            }
        }

        switch status {
        case .failed:
            if let error {
                let detail = [error.message, error.additionalDetails]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
                entries.append(
                    ConversationEntry(
                        id: "\(id)-failed",
                        kind: .notice,
                        title: "Turn failed",
                        body: detail,
                        footnote: nil,
                        isStreaming: false
                    )
                )
            }
        case .interrupted:
            entries.append(
                ConversationEntry(
                    id: "\(id)-interrupted",
                    kind: .notice,
                    title: "Turn interrupted",
                    body: "The response stopped before completion.",
                    footnote: nil,
                    isStreaming: false
                )
            )
        case .completed, .inProgress:
            break
        }

        return entries
    }
}

private extension Array<UserInputPayload> {
    var conversationText: String {
        map { item in
            switch item {
            case .text(let text):
                text
            case .image(let url):
                "[Image] \(url.absoluteString)"
            case .localImage(let path):
                "[Image] \(path)"
            case .skill(let name):
                "[Skill] \(name)"
            case .mention(let name):
                "@\(name)"
            case .unknown:
                ""
            }
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }
}

extension String {
    var humanizedProtocolLabel: String {
        replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func trimmedForPreview(maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else {
            return trimmed
        }

        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private extension RelativeDateTimeFormatter {
    static func makeCodexFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
