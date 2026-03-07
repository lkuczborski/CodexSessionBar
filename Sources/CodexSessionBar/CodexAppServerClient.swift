import Darwin
import Foundation

actor CodexAppServerClient {
    private let requestTimeout: TimeInterval = 8
    private var connection: AppServerConnection?
    private var eventContinuations: [UUID: AsyncStream<AppServerEvent>.Continuation] = [:]

    func fetchActiveSessions() async throws -> [ActiveSession] {
        let connection = try await sharedConnection()
        let threads = try await Self.collectAllPages { cursor in
            try await connection.listThreads(cursor: cursor)
        }

        return Self.selectTrackedSessions(
            threads: threads,
            now: Date(),
            recentWindow: 24 * 60 * 60
        )
    }

    private func sharedConnection() async throws -> AppServerConnection {
        if let connection {
            return connection
        }

        guard let codexExecutable = resolveCodexExecutable() else {
            throw ClientError.codexNotFound
        }

        let connection = AppServerConnection(
            codexExecutable: codexExecutable,
            requestTimeout: requestTimeout,
            eventSink: { [weak self] event in
                Task {
                    await self?.broadcast(event)
                }
            }
        )
        self.connection = connection
        return connection
    }

    func eventStream() -> AsyncStream<AppServerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                self.addEventContinuation(continuation, id: id)
            }

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeEventContinuation(id: id)
                }
            }
        }
    }

    static func collectAllPages<T>(
        fetchPage: (String?) async throws -> (data: [T], nextCursor: String?)
    ) async rethrows -> [T] {
        var allItems: [T] = []
        var cursor: String?

        while true {
            let page = try await fetchPage(cursor)
            allItems.append(contentsOf: page.data)

            guard let nextCursor = page.nextCursor, !nextCursor.isEmpty else {
                break
            }

            cursor = nextCursor
        }

        return allItems
    }

    static func selectTrackedSessions(
        threads: [CodexThread],
        now: Date,
        recentWindow: TimeInterval
    ) -> [ActiveSession] {
        let recentCutoff = now.addingTimeInterval(-recentWindow)

        let trackedThreads = threads.filter { thread in
            let updatedDate = Date(timeIntervalSince1970: thread.updatedAt)
            return thread.runtimeStatus.isLoaded || updatedDate >= recentCutoff
        }

        let sessions = trackedThreads.map { thread in
            ActiveSession(
                id: thread.id,
                preview: thread.preview,
                cwd: thread.cwd,
                path: thread.path,
                modelProvider: thread.modelProvider,
                source: thread.source,
                createdAt: Date(timeIntervalSince1970: thread.createdAt),
                updatedAt: Date(timeIntervalSince1970: thread.updatedAt),
                runtimeStatus: thread.runtimeStatus
            )
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func resolveCodexExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment

        if let path = environment["PATH"] {
            for pathEntry in path.split(separator: ":") {
                let candidate = String(pathEntry) + "/codex"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        let fallbackPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.local/bin/codex"
        ]

        return fallbackPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func addEventContinuation(
        _ continuation: AsyncStream<AppServerEvent>.Continuation,
        id: UUID
    ) {
        eventContinuations[id] = continuation
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func broadcast(_ event: AppServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}

private actor AppServerConnection {
    private let codexExecutable: String
    private let requestTimeout: TimeInterval
    private let jsonDecoder = JSONDecoder()
    private let eventSink: @Sendable (AppServerEvent) -> Void

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var nextRequestID = 1
    private var pendingResponses: [Int: CheckedContinuation<ResponsePayload, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var didSendInitialized = false
    private var processTerminationReason: String?

    init(
        codexExecutable: String,
        requestTimeout: TimeInterval,
        eventSink: @escaping @Sendable (AppServerEvent) -> Void
    ) {
        self.codexExecutable = codexExecutable
        self.requestTimeout = requestTimeout
        self.eventSink = eventSink
    }

    func listThreads(cursor: String?) async throws -> (data: [CodexThread], nextCursor: String?) {
        let response: ThreadListResponse = try await sendRequest(
            method: "thread/list",
            params: ThreadListParams(
                cursor: cursor,
                limit: 250,
                sortKey: "updated_at",
                archived: false,
                sourceKinds: SessionSourceKind.threadListFilterValues
            )
        )
        return (response.data, response.nextCursor)
    }

    private func sendRequest<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params
    ) async throws -> Response {
        try await ensureConnected()

        let id = nextRequestID
        nextRequestID += 1

        let payload = try JSONEncoder().encode(AnyEncodable(RequestEnvelope(id: id, method: method, params: params)))
        let response = try await sendPayload(payload, id: id)
        return try decodeResult(from: response)
    }

    private func ensureConnected() async throws {
        if process != nil, didSendInitialized {
            return
        }

        try startProcess()

        do {
            let initializeResponse = try await sendPayload(
                JSONEncoder().encode(
                    AnyEncodable(
                        RequestEnvelope(
                            id: nextRequestID,
                            method: "initialize",
                            params: InitializeParams(
                                clientInfo: InitializeClientInfo(
                                    name: "codex-session-bar",
                                    title: "Codex Session Bar",
                                    version: "0.4.0"
                                ),
                                capabilities: InitializeCapabilities(experimentalApi: true)
                            )
                        )
                    )
                ),
                id: nextRequestID
            )
            nextRequestID += 1

            let _: InitializeResponse = try decodeResult(from: initializeResponse)
            try sendNotification(method: "initialized", params: EmptyParams())
            didSendInitialized = true
        } catch {
            await handleTransportFailure(error)
            throw error
        }
    }

    private func startProcess() throws {
        guard process == nil else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleProcessTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            throw ClientError.processLaunchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.processTerminationReason = nil
        self.didSendInitialized = false

        try configureReadSource(
            handle: stdoutPipe.fileHandleForReading,
            existingSource: &stdoutSource,
            append: { [weak self] data in
                Task { await self?.consumeStdout(data) }
            },
            fail: { [weak self] error in
                Task { await self?.handleTransportFailure(error) }
            }
        )

        try configureReadSource(
            handle: stderrPipe.fileHandleForReading,
            existingSource: &stderrSource,
            append: { [weak self] data in
                Task { await self?.appendStderr(data) }
            },
            fail: { [weak self] error in
                Task { await self?.handleTransportFailure(error) }
            }
        )
    }

    private func configureReadSource(
        handle: FileHandle,
        existingSource: inout DispatchSourceRead?,
        append: @escaping @Sendable (Data) -> Void,
        fail: @escaping @Sendable (ClientError) -> Void
    ) throws {
        existingSource?.cancel()

        let fileDescriptor = handle.fileDescriptor
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags == -1 || fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw ClientError.stdoutSetupFailed
        }

        let queue = DispatchQueue(label: "CodexSessionBar.\(fileDescriptor)")
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        source.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 4096)
            var buffered = Data()

            while true {
                let readCount = Darwin.read(fileDescriptor, &chunk, chunk.count)
                if readCount > 0 {
                    buffered.append(contentsOf: chunk.prefix(readCount))
                    continue
                }

                if readCount == 0 {
                    break
                }

                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }

                fail(.stdoutReadFailed(String(cString: strerror(errno))))
                return
            }

            if !buffered.isEmpty {
                append(buffered)
            }
        }
        source.resume()
        existingSource = source
    }

    private func sendNotification<Params: Encodable>(
        method: String,
        params: Params
    ) throws {
        guard let stdinHandle else {
            throw ClientError.disconnected
        }

        let payload = try JSONEncoder().encode(AnyEncodable(NotificationEnvelope(method: method, params: params)))
        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))
    }

    private func sendPayload(_ payload: Data, id: Int) async throws -> ResponsePayload {
        guard let stdinHandle else {
            throw ClientError.disconnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            timeoutTasks[id] = Task { [requestTimeout] in
                try? await Task.sleep(for: .seconds(requestTimeout))
                await self.handleRequestTimeout(id: id, timeout: requestTimeout)
            }

            stdinHandle.write(payload)
            stdinHandle.write(Data([0x0A]))
        }
    }

    private func handleRequestTimeout(id: Int, timeout: TimeInterval) async {
        guard let continuation = pendingResponses.removeValue(forKey: id) else {
            return
        }

        timeoutTasks.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: ClientError.requestTimedOut(timeout, cachedStderrText()))
        await handleTransportFailure(ClientError.requestTimedOut(timeout, cachedStderrText()))
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            var lineData = stdoutBuffer.prefix(upTo: newlineIndex)
            stdoutBuffer.removeSubrange(...newlineIndex)

            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }

            processLine(Data(lineData))
        }
    }

    private func appendStderr(_ data: Data) {
        stderrBuffer.append(data)
    }

    private func processLine(_ line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any]
        else {
            return
        }

        if let response = makeResponsePayload(from: dictionary) {
            timeoutTasks.removeValue(forKey: response.id)?.cancel()
            pendingResponses.removeValue(forKey: response.id)?.resume(returning: response.payload)
            return
        }

        if let method = dictionary["method"] as? String {
            handleServerMessage(method: method)
        }
    }

    private func makeResponsePayload(from dictionary: [String: Any]) -> (id: Int, payload: ResponsePayload)? {
        guard let id = parseRequestID(from: dictionary["id"]) else {
            return nil
        }

        if dictionary["result"] != nil || dictionary["error"] != nil {
            let resultData = dictionary["result"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            let errorMessage = (dictionary["error"] as? [String: Any])?["message"] as? String
            return (id, ResponsePayload(resultData: resultData, errorMessage: errorMessage))
        }

        return nil
    }

    private func handleServerMessage(method: String) {
        guard let event = AppServerEvent(method: method) else {
            return
        }

        eventSink(event)
    }

    private func handleProcessTermination(status: Int32) async {
        guard process != nil else {
            return
        }

        processTerminationReason = "exit status \(status)"
        await handleTransportFailure(ClientError.processFailed(cachedStderrText()))
    }

    private func handleTransportFailure(_ error: Error) async {
        let pending = pendingResponses
        let timeouts = timeoutTasks

        pendingResponses.removeAll()
        timeoutTasks.removeAll()
        stdoutBuffer.removeAll(keepingCapacity: true)
        didSendInitialized = false

        for task in timeouts.values {
            task.cancel()
        }

        for continuation in pending.values {
            continuation.resume(throwing: error)
        }

        stdoutSource?.cancel()
        stderrSource?.cancel()
        stdoutSource = nil
        stderrSource = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func decodeResult<T: Decodable>(from response: ResponsePayload) throws -> T {
        if let errorMessage = response.errorMessage {
            throw ClientError.rpcError(errorMessage)
        }

        guard let resultData = response.resultData else {
            throw ClientError.missingResult
        }

        return try jsonDecoder.decode(T.self, from: resultData)
    }

    private func parseRequestID(from value: Any?) -> Int? {
        if let id = value as? Int {
            return id
        }

        if let idString = value as? String {
            return Int(idString)
        }

        return nil
    }

    private func cachedStderrText() -> String {
        let text = String(data: stderrBuffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let text, !text.isEmpty {
            return text
        }

        if let processTerminationReason {
            return processTerminationReason
        }

        return "Unknown app-server error"
    }
}

enum AppServerEvent: Equatable, Sendable {
    case sessionsChanged(reason: String)

    init?(method: String) {
        switch method {
        case "thread/started",
             "thread/status/changed",
             "thread/archived",
             "thread/unarchived",
             "thread/closed",
             "turn/started",
             "turn/completed",
             "serverRequest/resolved",
             "error":
            self = .sessionsChanged(reason: method)
        default:
            return nil
        }
    }
}

private struct ResponsePayload: Sendable {
    let resultData: Data?
    let errorMessage: String?
}

private struct RequestEnvelope<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

private struct NotificationEnvelope<Params: Encodable>: Encodable {
    let method: String
    let params: Params
}

private struct EmptyParams: Encodable {}

private struct InitializeParams: Encodable {
    let clientInfo: InitializeClientInfo
    let capabilities: InitializeCapabilities
}

private struct InitializeClientInfo: Encodable {
    let name: String
    let title: String?
    let version: String
}

private struct InitializeCapabilities: Encodable {
    let experimentalApi: Bool
}

private struct InitializeResponse: Decodable {
    let userAgent: String
}

private struct ThreadListParams: Encodable {
    let cursor: String?
    let limit: Int
    let sortKey: String
    let archived: Bool
    let sourceKinds: [SessionSourceKind]
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        self.encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

enum ClientError: LocalizedError {
    case codexNotFound
    case disconnected
    case processLaunchFailed(String)
    case processFailed(String)
    case requestTimedOut(TimeInterval, String)
    case stdoutSetupFailed
    case stdoutReadFailed(String)
    case missingResult
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Could not find the codex executable. Install Codex CLI or add it to PATH."
        case .disconnected:
            return "The Codex app-server connection is not available."
        case .processLaunchFailed(let reason):
            return "Failed to launch codex app-server: \(reason)"
        case .processFailed(let stderr):
            return "codex app-server exited with an error: \(stderr)"
        case .requestTimedOut(let seconds, let stderr):
            return "codex app-server timed out after \(Int(seconds))s: \(stderr)"
        case .stdoutSetupFailed:
            return "Failed to configure app-server output stream."
        case .stdoutReadFailed(let reason):
            return "Failed to read app-server output: \(reason)"
        case .missingResult:
            return "Missing result payload in app-server response."
        case .rpcError(let message):
            return "Codex app-server error: \(message)"
        }
    }
}
