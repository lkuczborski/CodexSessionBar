import Foundation

struct ActiveSession: Identifiable, Equatable {
    let id: String
    let preview: String
    let cwd: String
    let path: String?
    let modelProvider: String
    let source: SessionSourceKind
    let createdAt: Date
    let updatedAt: Date
    let runtimeStatus: ThreadStatus

    var displayTitle: String {
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(No preview text)" : trimmed
    }

    var sourceLabel: String {
        source.displayLabel
    }

    var updatedRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var createdRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var isLive: Bool {
        runtimeStatus.isLoaded
    }

    var activityLabel: String {
        runtimeStatus.displayLabel
    }
}

enum SessionSourceKind: String, Codable, CaseIterable {
    case cli
    case vscode
    case exec
    case appServer
    case subAgent
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknown

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let rawValue = try? container.decode(String.self) {
            self = SessionSourceKind(rawValue: rawValue) ?? .unknown
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let subAgent = try? container.decode(String.self, forKey: .subAgent) {
            switch subAgent {
            case "review":
                self = .subAgentReview
            case "compact":
                self = .subAgentCompact
            case "threadSpawn":
                self = .subAgentThreadSpawn
            case "other":
                self = .subAgentOther
            default:
                self = .subAgent
            }
            return
        }

        self = .unknown
    }

    static var threadListFilterValues: [SessionSourceKind] {
        allCases.filter { $0 != .unknown }
    }

    var displayLabel: String {
        switch self {
        case .cli: return "CLI"
        case .vscode: return "VS Code"
        case .exec: return "Exec"
        case .appServer: return "App Server"
        case .subAgent: return "Sub-agent"
        case .subAgentReview: return "Sub-agent Review"
        case .subAgentCompact: return "Sub-agent Compact"
        case .subAgentThreadSpawn: return "Sub-agent Spawn"
        case .subAgentOther: return "Sub-agent Other"
        case .unknown: return "Unknown"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case subAgent
    }
}

struct ThreadListResponse: Decodable {
    let data: [CodexThread]
    let nextCursor: String?
}

struct CodexThread: Decodable {
    let id: String
    let preview: String
    let modelProvider: String
    let createdAt: TimeInterval
    let updatedAt: TimeInterval
    let status: ThreadStatus?
    let path: String?
    let cwd: String
    let source: SessionSourceKind

    var runtimeStatus: ThreadStatus {
        status ?? .notLoaded
    }
}

enum ThreadStatusType: String, Decodable {
    case notLoaded
    case idle
    case systemError
    case active
    case unknown

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThreadStatusType(rawValue: rawValue) ?? .unknown
    }
}

struct ThreadStatus: Decodable, Equatable {
    let type: ThreadStatusType
    let activeFlags: [String]

    init(type: ThreadStatusType, activeFlags: [String] = []) {
        self.type = type
        self.activeFlags = activeFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = (try? container.decode(ThreadStatusType.self, forKey: .type)) ?? .unknown
        self.activeFlags = (try? container.decode([String].self, forKey: .activeFlags)) ?? []
    }

    var isLoaded: Bool {
        switch type {
        case .notLoaded:
            return false
        case .idle, .systemError, .active, .unknown:
            return true
        }
    }

    var displayLabel: String {
        switch type {
        case .active:
            return activeFlags.isEmpty ? "Active" : activeFlags.joined(separator: ", ")
        case .idle:
            return "Idle"
        case .systemError:
            return "System Error"
        case .notLoaded:
            return "Stored"
        case .unknown:
            return "Live"
        }
    }

    static let notLoaded = ThreadStatus(type: .notLoaded)

    private enum CodingKeys: String, CodingKey {
        case type
        case activeFlags
    }
}
