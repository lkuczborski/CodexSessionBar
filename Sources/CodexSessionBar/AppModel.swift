import Foundation
import Observation

@MainActor
@Observable
final class CodexMiniAppModel {
    private(set) var sessions: [SessionSummary] = []
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing: Bool = false
    private(set) var activeSessionRoute: ChatWindowRoute?

    @ObservationIgnored
    private let client: CodexAppServerClient
    @ObservationIgnored
    private var didStart = false
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var scheduledRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private var cachedRecords: [String: SessionRecord] = [:]
    @ObservationIgnored
    private var windowModels: [String: ChatWindowModel] = [:]
    @ObservationIgnored
    private let defaultDraftRoute = ChatWindowRoute.draft()

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        autostart: Bool = true
    ) {
        self.client = client
        if autostart {
            startIfNeeded()
        }
    }

    var liveCount: Int {
        sessions.filter(\.isLive).count
    }

    var menuBarTitle: String {
        liveCount > 0 ? "Codex \(liveCount)" : "Codex"
    }

    var menuBarSymbol: String {
        liveCount > 0 ? "ellipsis.message.fill" : "ellipsis.message"
    }

    var recentSessions: [SessionSummary] {
        Array(sessions.prefix(6))
    }

    var recentSwitcherSessions: [SessionSummary] {
        Array(sessions.prefix(5))
    }

    var displayedSessionRoute: ChatWindowRoute {
        if let activeSessionRoute {
            return activeSessionRoute
        }

        return mostRecentSessionRoute ?? defaultDraftRoute
    }

    var activeSessionModel: ChatWindowModel {
        windowModel(for: displayedSessionRoute)
    }

    func startIfNeeded() {
        guard !didStart else {
            return
        }

        didStart = true

        observationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let stream = await client.eventStream()
            for await event in stream {
                await MainActor.run {
                    self.handle(event)
                }
            }
        }

        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            await refreshNow()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
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
            let sessions = try await client.fetchSessions()
            self.sessions = sessions
            lastRefresh = Date()
            lastError = nil
            syncDisplayedRouteIfNeeded()
            applyLatestSummariesToWindows()
            hydrateDisplayedSessionIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func windowModel(for route: ChatWindowRoute) -> ChatWindowModel {
        if let existing = windowModels[route.rawValue] {
            return existing
        }

        if let threadID = route.threadID,
           let existing = windowModels.values.first(where: { $0.threadID == threadID }) {
            windowModels[route.rawValue] = existing
            return existing
        }

        let threadID = route.threadID
        let model = ChatWindowModel(
            route: route,
            initialSummary: threadID.flatMap(sessionSummary(for:)),
            initialRecord: threadID.flatMap { cachedRecords[$0] },
            fallbackWorkingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            client: client,
            owner: self
        )
        windowModels[route.rawValue] = model
        return model
    }

    func selectSession(_ route: ChatWindowRoute) {
        activeSessionRoute = route
        let model = windowModel(for: route)
        model.refreshThreadContents()
    }

    func createFreshSession() {
        selectSession(.draft())
    }

    func store(record: SessionRecord) {
        cachedRecords[record.summary.id] = record
        merge(summary: record.summary)

        for windowModel in windowModels.values where windowModel.threadID == record.summary.id {
            windowModel.replace(with: record)
        }
    }

    func merge(summary: SessionSummary) {
        if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
            sessions[index] = summary
        } else {
            sessions.append(summary)
        }

        sessions.sort { $0.updatedAt > $1.updatedAt }
        syncDisplayedRouteIfNeeded()
    }

    func bindWindowModel(_ windowModel: ChatWindowModel, to threadID: String) {
        windowModels[ChatWindowRoute.thread(threadID).rawValue] = windowModel

        if activeSessionRoute?.rawValue == windowModel.route.rawValue,
           activeSessionRoute?.threadID == nil {
            activeSessionRoute = .thread(threadID)
        }
    }

    private func scheduleRefreshSoon() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else {
                return
            }

            await refreshNow()
        }
    }

    func sessionSummary(for id: String) -> SessionSummary? {
        sessions.first(where: { $0.id == id })
    }

    private func handle(_ event: AppServerEvent) {
        switch event {
        case .sessionsChanged:
            scheduleRefreshSoon()

        case .turnStarted, .turnCompleted, .agentMessageDelta, .serverNotice:
            for windowModel in windowModels.values {
                windowModel.handle(event)
            }

            switch event {
            case .turnCompleted:
                scheduleRefreshSoon()
            case .serverNotice(_, let tone, let message) where tone == .failure:
                lastError = message
            default:
                break
            }

        case .error(let message):
            lastError = message
        }
    }

    private func applyLatestSummariesToWindows() {
        for windowModel in windowModels.values {
            guard let threadID = windowModel.threadID else {
                continue
            }

            windowModel.apply(latestSummary: sessionSummary(for: threadID))
        }
    }

    private func hydrateDisplayedSessionIfNeeded() {
        guard let threadID = displayedSessionRoute.threadID,
              let latestSummary = sessionSummary(for: threadID) else {
            return
        }

        let cachedSummary = cachedRecords[threadID]?.summary
        let needsHydration = Self.shouldHydrateThreadRecord(
            cachedSummary: cachedSummary,
            latestSummary: latestSummary
        )
        guard needsHydration else {
            return
        }

        windowModel(for: .thread(threadID)).refreshThreadContents()
    }

    nonisolated static func shouldHydrateThreadRecord(
        cachedSummary: SessionSummary?,
        latestSummary: SessionSummary
    ) -> Bool {
        cachedSummary?.updatedAt != latestSummary.updatedAt
    }

    private func syncDisplayedRouteIfNeeded() {
        guard let activeSessionRoute,
              let threadID = activeSessionRoute.threadID else {
            return
        }

        guard !sessions.contains(where: { $0.id == threadID }) else {
            return
        }

        self.activeSessionRoute = mostRecentSessionRoute
    }

    private var mostRecentSessionRoute: ChatWindowRoute? {
        sessions.first.map { ChatWindowRoute.thread($0.id) }
    }
}
