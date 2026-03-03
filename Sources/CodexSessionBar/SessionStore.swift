import AppKit
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [ActiveSession] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var statusText: String = "Starting..."
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing: Bool = false

    var menuBarTitle: String {
        if sessions.isEmpty {
            return "Codex"
        }

        let loadedCount = sessions.filter(\.isLoaded).count
        if loadedCount > 0 {
            return "Codex \(loadedCount)"
        }

        return "Codex \(sessions.count)"
    }

    var menuBarSymbol: String {
        sessions.isEmpty ? "terminal" : "dot.radiowaves.left.and.right"
    }

    private let client = CodexAppServerClient()
    private var pollingTask: Task<Void, Never>?
    private var didStart = false

    init() {
        startIfNeeded()
    }

    func startIfNeeded() {
        guard !didStart else {
            return
        }

        didStart = true
        pollingTask = Task {
            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                await refreshNow()
            }
        }
    }

    func refreshNow() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let sessions = try await client.fetchActiveSessions()
            self.sessions = sessions
            self.lastRefresh = Date()
            self.lastError = nil

            let loadedCount = sessions.filter(\.isLoaded).count
            if sessions.isEmpty {
                statusText = "No tracked sessions"
            } else if loadedCount == 0 {
                statusText = "\(sessions.count) recent sessions"
            } else if loadedCount == 1 {
                statusText = "1 loaded, \(sessions.count) tracked"
            } else {
                statusText = "\(loadedCount) loaded, \(sessions.count) tracked"
            }
        } catch {
            lastError = error.localizedDescription
            statusText = "Unable to load sessions"
        }
    }

    func copySessionID(_ session: ActiveSession) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.id, forType: .string)
    }

    func openWorkingDirectory(_ session: ActiveSession) {
        guard !session.cwd.isEmpty else {
            return
        }

        let directoryURL = URL(fileURLWithPath: session.cwd)
        NSWorkspace.shared.open(directoryURL)
    }

    func revealThreadPath(_ session: ActiveSession) {
        guard let path = session.path, !path.isEmpty else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    deinit {
        pollingTask?.cancel()
    }
}
