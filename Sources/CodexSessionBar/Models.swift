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
    let isLoaded: Bool

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

    var cwdLastComponent: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var activityLabel: String {
        isLoaded ? "Loaded" : "Recent"
    }
}

enum SessionSourceKind: String, Decodable {
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
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = SessionSourceKind(rawValue: rawValue) ?? .unknown
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
}

struct ThreadLoadedListResponse: Decodable {
    let data: [String]
    let nextCursor: String?
}

struct ThreadListResponse: Decodable {
    let data: [CodexThread]
    let nextCursor: String?
}

struct ThreadReadResponse: Decodable {
    let thread: CodexThread
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
}

struct ThreadStatus: Decodable {
    let type: String
}
