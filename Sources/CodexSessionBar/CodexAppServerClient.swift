import Darwin
import Foundation

actor CodexAppServerClient {
    private let requestTimeout: TimeInterval = 15
    private var connection: AppServerConnection?
    private var eventContinuations: [UUID: AsyncStream<AppServerEvent>.Continuation] = [:]

    func fetchModels() async throws -> [CodexModel] {
        let connection = try await sharedConnection()
        let models = try await Self.collectAllPages { cursor in
            try await connection.listModels(cursor: cursor)
        }

        return models
            .filter { !$0.hidden }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }

                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    func fetchSessions() async throws -> [SessionSummary] {
        let connection = try await sharedConnection()
        let threads = try await Self.collectAllPages { cursor in
            try await connection.listThreads(cursor: cursor)
        }

        return threads
            .map(\.sessionSummary)
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func fetchThreadRecord(threadID: String) async throws -> SessionRecord {
        let connection = try await sharedConnection()
        let response = try await connection.readThread(id: threadID)
        return response.thread.sessionRecord
    }

    func startThread(cwd: String, model: String?, serviceTier: ServiceTierValue?) async throws -> SessionSummary {
        let connection = try await sharedConnection()
        let response = try await connection.startThread(cwd: cwd, model: model, serviceTier: serviceTier)
        return response.thread.sessionSummary
    }

    func resumeThread(id: String, cwd: String?, model: String?, serviceTier: ServiceTierValue?) async throws -> SessionRecord {
        let connection = try await sharedConnection()
        let response = try await connection.resumeThread(id: id, cwd: cwd, model: model, serviceTier: serviceTier)
        return response.thread.sessionRecord
    }

    func startTurn(
        threadID: String,
        prompt: String,
        cwd: String?,
        model: String?,
        effort: ReasoningEffortValue?,
        serviceTier: ServiceTierValue?
    ) async throws -> String {
        let connection = try await sharedConnection()
        let response = try await connection.startTurn(
            threadID: threadID,
            prompt: prompt,
            cwd: cwd,
            model: model,
            effort: effort,
            serviceTier: serviceTier
        )
        return response.turn.id
    }

    func eventStream() -> AsyncStream<AppServerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            addEventContinuation(continuation, id: id)

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
    private let jsonEncoder = JSONEncoder()
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
                limit: 200,
                sortKey: "updated_at",
                modelProviders: nil,
                sourceKinds: SessionSourceKind.threadListFilterValues,
                archived: false,
                cwd: nil,
                searchTerm: nil
            )
        )
        return (response.data, response.nextCursor)
    }

    func listModels(cursor: String?) async throws -> (data: [CodexModel], nextCursor: String?) {
        let response: ModelListResponse = try await sendRequest(
            method: "model/list",
            params: ModelListParams(
                cursor: cursor,
                includeHidden: false,
                limit: 100
            )
        )
        return (response.data, response.nextCursor)
    }

    func readThread(id: String) async throws -> ThreadReadResponse {
        try await sendRequest(
            method: "thread/read",
            params: ThreadReadParams(threadId: id, includeTurns: true)
        )
    }

    func startThread(cwd: String, model: String?, serviceTier: ServiceTierValue?) async throws -> ThreadStartResponse {
        try await sendRequest(
            method: "thread/start",
            params: ThreadStartParams(
                model: model,
                cwd: cwd,
                approvalPolicy: "never",
                sandbox: "workspace-write",
                experimentalRawEvents: false,
                persistExtendedHistory: true,
                serviceTier: serviceTier
            )
        )
    }

    func resumeThread(
        id: String,
        cwd: String?,
        model: String?,
        serviceTier: ServiceTierValue?
    ) async throws -> ThreadResumeResponse {
        try await sendRequest(
            method: "thread/resume",
            params: ThreadResumeParams(
                threadId: id,
                model: model,
                cwd: cwd,
                approvalPolicy: "never",
                sandbox: "workspace-write",
                persistExtendedHistory: true,
                serviceTier: serviceTier
            )
        )
    }

    func startTurn(
        threadID: String,
        prompt: String,
        cwd: String?,
        model: String?,
        effort: ReasoningEffortValue?,
        serviceTier: ServiceTierValue?
    ) async throws -> TurnStartResponse {
        try await sendRequest(
            method: "turn/start",
            params: TurnStartParams(
                threadId: threadID,
                input: [.text(prompt)],
                cwd: cwd,
                approvalPolicy: "never",
                model: model,
                effort: effort,
                serviceTier: serviceTier
            )
        )
    }

    private func sendRequest<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params
    ) async throws -> Response {
        try await ensureConnected()

        let id = nextRequestID
        nextRequestID += 1

        let payload = try jsonEncoder.encode(AnyEncodable(RequestEnvelope(id: id, method: method, params: params)))
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
                jsonEncoder.encode(
                    AnyEncodable(
                        RequestEnvelope(
                            id: nextRequestID,
                            method: "initialize",
                            params: InitializeParams(
                                clientInfo: InitializeClientInfo(
                                    name: "codex-session-bar",
                                    title: "Codex Mini Sessions",
                                    version: "1.0.0"
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

        let payload = try jsonEncoder.encode(AnyEncodable(NotificationEnvelope(method: method, params: params)))
        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))
    }

    private func sendServerResponse<Result: Encodable>(id: Int, result: Result) throws {
        guard let stdinHandle else {
            throw ClientError.disconnected
        }

        let payload = try jsonEncoder.encode(AnyEncodable(ResponseEnvelope(id: id, result: result)))
        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))
    }

    private func sendServerError(id: Int, message: String) throws {
        guard let stdinHandle else {
            throw ClientError.disconnected
        }

        let payload = try jsonEncoder.encode(AnyEncodable(ErrorResponseEnvelope(id: id, error: RPCError(message: message))))
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

        guard let method = dictionary["method"] as? String else {
            return
        }

        let paramsData: Data?
        if let params = dictionary["params"] {
            paramsData = try? JSONSerialization.data(withJSONObject: params)
        } else {
            paramsData = nil
        }

        if let id = parseRequestID(from: dictionary["id"]) {
            Task {
                await handleServerRequest(id: id, method: method, paramsData: paramsData)
            }
        } else {
            handleServerNotification(method: method, paramsData: paramsData)
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

    private func handleServerNotification(method: String, paramsData: Data?) {
        switch method {
        case "thread/started",
             "thread/status/changed",
             "thread/archived",
             "thread/unarchived",
             "thread/closed",
             "thread/name/updated",
             "thread/tokenUsage/updated":
            eventSink(.sessionsChanged(reason: method))

        case "turn/started":
            if let payload: TurnLifecyclePayload = decodePayload(from: paramsData) {
                eventSink(.turnStarted(threadID: payload.threadId, turnID: payload.turn.id))
            }
            eventSink(.sessionsChanged(reason: method))

        case "turn/completed":
            if let payload: TurnLifecyclePayload = decodePayload(from: paramsData) {
                eventSink(.turnCompleted(threadID: payload.threadId, turnID: payload.turn.id))
            }
            eventSink(.sessionsChanged(reason: method))

        case "item/agentMessage/delta":
            if let payload: AgentMessageDeltaPayload = decodePayload(from: paramsData) {
                eventSink(
                    .agentMessageDelta(
                        threadID: payload.threadId,
                        turnID: payload.turnId,
                        itemID: payload.itemId,
                        delta: payload.delta
                    )
                )
            }

        case "error":
            let message = decodePayload(from: paramsData, as: ErrorNotificationPayload.self)?.message ?? "Unknown app-server error."
            eventSink(.error(message))

        case "serverRequest/resolved",
             "item/completed",
             "thread/compacted",
             "configWarning":
            eventSink(.sessionsChanged(reason: method))

        default:
            break
        }
    }

    private func handleServerRequest(id: Int, method: String, paramsData: Data?) async {
        do {
            switch method {
            case "item/commandExecution/requestApproval":
                let payload: CommandExecutionApprovalRequestPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: CommandExecutionApprovalDecisionPayload(decision: "decline"))
                eventSink(.serverNotice(threadID: payload.threadId, tone: .warning, message: "A command execution request was declined in the mini window shell."))

            case "item/fileChange/requestApproval":
                let payload: FileChangeApprovalRequestPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: FileChangeApprovalDecisionPayload(decision: "decline"))
                eventSink(.serverNotice(threadID: payload.threadId, tone: .warning, message: "A file change request was declined in the mini window shell."))

            case "item/permissions/requestApproval":
                let payload: PermissionsRequestPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: PermissionsApprovalResponsePayload(permissions: EmptyPermissionsPayload(), scope: "turn"))
                eventSink(.serverNotice(threadID: payload.threadId, tone: .warning, message: payload.reason ?? "Additional permissions were requested and denied."))

            case "item/tool/requestUserInput":
                let payload: ToolRequestUserInputRequestPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: ToolRequestUserInputResponsePayload(answers: [:]))
                eventSink(.serverNotice(threadID: payload.threadId, tone: .warning, message: "Codex requested extra user input, but the mini window does not yet support interactive prompts."))

            case "mcpServer/elicitation/request":
                try sendServerResponse(id: id, result: McpServerElicitationResponsePayload(action: "cancel", content: nil, meta: nil))
                eventSink(.serverNotice(threadID: nil, tone: .warning, message: "An MCP elicitation request was cancelled in the lightweight shell."))

            case "item/tool/call":
                let payload: DynamicToolCallRequestPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(
                    id: id,
                    result: DynamicToolCallResponsePayload(
                        contentItems: [.init(type: "inputText", text: "Dynamic tool calls are not supported in the mini window shell yet.")],
                        success: false
                    )
                )
                eventSink(.serverNotice(threadID: payload.threadId, tone: .warning, message: "Codex attempted a dynamic tool call that this mini shell does not implement yet."))

            case "account/chatgptAuthTokens/refresh":
                try sendServerError(id: id, message: "Auth token refresh is not supported by this client.")

            case "applyPatchApproval":
                let payload: LegacyConversationPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: LegacyReviewDecisionPayload(decision: "denied"))
                eventSink(.serverNotice(threadID: payload.conversationId, tone: .warning, message: "A patch approval request was denied in the mini window shell."))

            case "execCommandApproval":
                let payload: LegacyConversationPayload = decodePayload(from: paramsData) ?? .empty
                try sendServerResponse(id: id, result: LegacyReviewDecisionPayload(decision: "denied"))
                eventSink(.serverNotice(threadID: payload.conversationId, tone: .warning, message: "A command approval request was denied in the mini window shell."))

            default:
                try sendServerError(id: id, message: "Unsupported server request: \(method)")
                eventSink(.serverNotice(threadID: nil, tone: .warning, message: "Unsupported app-server request: \(method)"))
            }
        } catch {
            eventSink(.error("Failed to answer app-server request \(method): \(error.localizedDescription)"))
        }
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

    private func decodePayload<T: Decodable>(from paramsData: Data?, as type: T.Type = T.self) -> T? {
        guard let paramsData else {
            return nil
        }

        return try? jsonDecoder.decode(T.self, from: paramsData)
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
    case turnStarted(threadID: String, turnID: String)
    case turnCompleted(threadID: String, turnID: String)
    case agentMessageDelta(threadID: String, turnID: String, itemID: String, delta: String)
    case serverNotice(threadID: String?, tone: SessionBanner.Tone, message: String)
    case error(String)
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

private struct ResponseEnvelope<Result: Encodable>: Encodable {
    let id: Int
    let result: Result
}

private struct ErrorResponseEnvelope: Encodable {
    let id: Int
    let error: RPCError
}

private struct RPCError: Encodable {
    let message: String
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
    let userAgent: String?
}

private struct ThreadListParams: Encodable {
    let cursor: String?
    let limit: Int
    let sortKey: String
    let modelProviders: [String]?
    let sourceKinds: [SessionSourceKind]
    let archived: Bool
    let cwd: String?
    let searchTerm: String?
}

private struct ModelListParams: Encodable {
    let cursor: String?
    let includeHidden: Bool?
    let limit: Int?
}

private struct ThreadReadParams: Encodable {
    let threadId: String
    let includeTurns: Bool
}

private struct ThreadStartParams: Encodable {
    let model: String?
    let modelProvider: String? = nil
    let cwd: String?
    let approvalPolicy: String?
    let sandbox: String?
    let config: [String: JSONValue]? = nil
    let serviceName: String? = nil
    let baseInstructions: String? = nil
    let developerInstructions: String? = nil
    let personality: String? = nil
    let ephemeral: Bool? = nil
    let experimentalRawEvents: Bool
    let persistExtendedHistory: Bool
    let serviceTier: ServiceTierValue?
}

private struct ThreadResumeParams: Encodable {
    let threadId: String
    let history: [JSONValue]? = nil
    let path: String? = nil
    let model: String?
    let modelProvider: String? = nil
    let cwd: String?
    let approvalPolicy: String?
    let sandbox: String?
    let config: [String: JSONValue]? = nil
    let baseInstructions: String? = nil
    let developerInstructions: String? = nil
    let personality: String? = nil
    let persistExtendedHistory: Bool
    let serviceTier: ServiceTierValue?
}

private struct TurnStartParams: Encodable {
    let threadId: String
    let input: [TurnUserInput]
    let cwd: String?
    let approvalPolicy: String?
    let model: String?
    let effort: ReasoningEffortValue?
    let serviceTier: ServiceTierValue?
}

private enum TurnUserInput: Encodable {
    case text(String)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode([String](), forKey: .textElements)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case textElements = "text_elements"
    }
}

private enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

private struct AgentMessageDeltaPayload: Decodable {
    let threadId: String
    let turnId: String
    let itemId: String
    let delta: String
}

private struct TurnLifecyclePayload: Decodable {
    let threadId: String
    let turn: TurnPayload
}

private struct TurnPayload: Decodable {
    let id: String
}

private struct ErrorNotificationPayload: Decodable {
    let message: String
}

private struct CommandExecutionApprovalRequestPayload: Decodable {
    let threadId: String?

    static let empty = CommandExecutionApprovalRequestPayload(threadId: nil)
}

private struct FileChangeApprovalRequestPayload: Decodable {
    let threadId: String?

    static let empty = FileChangeApprovalRequestPayload(threadId: nil)
}

private struct PermissionsRequestPayload: Decodable {
    let threadId: String?
    let reason: String?

    static let empty = PermissionsRequestPayload(threadId: nil, reason: nil)
}

private struct ToolRequestUserInputRequestPayload: Decodable {
    let threadId: String?

    static let empty = ToolRequestUserInputRequestPayload(threadId: nil)
}

private struct DynamicToolCallRequestPayload: Decodable {
    let threadId: String?

    static let empty = DynamicToolCallRequestPayload(threadId: nil)
}

private struct LegacyConversationPayload: Decodable {
    let conversationId: String?

    static let empty = LegacyConversationPayload(conversationId: nil)
}

private struct CommandExecutionApprovalDecisionPayload: Encodable {
    let decision: String
}

private struct FileChangeApprovalDecisionPayload: Encodable {
    let decision: String
}

private struct PermissionsApprovalResponsePayload: Encodable {
    let permissions: EmptyPermissionsPayload
    let scope: String
}

private struct EmptyPermissionsPayload: Encodable {}

private struct ToolRequestUserInputResponsePayload: Encodable {
    let answers: [String: EmptyToolAnswerPayload]
}

private struct EmptyToolAnswerPayload: Encodable {}

private struct McpServerElicitationResponsePayload: Encodable {
    let action: String
    let content: JSONValue?

    enum CodingKeys: String, CodingKey {
        case action
        case content
        case meta = "_meta"
    }

    let meta: JSONValue?
}

private struct DynamicToolCallResponsePayload: Encodable {
    let contentItems: [DynamicToolCallOutputItemPayload]
    let success: Bool
}

private struct DynamicToolCallOutputItemPayload: Encodable {
    let type: String
    let text: String?
    let imageUrl: String? = nil
}

private struct LegacyReviewDecisionPayload: Encodable {
    let decision: String
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
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
            return "Could not find the `codex` executable. Install the Codex CLI or add it to `PATH`."
        case .disconnected:
            return "The Codex app-server connection is not available."
        case .processLaunchFailed(let reason):
            return "Failed to launch `codex app-server`: \(reason)"
        case .processFailed(let stderr):
            return "`codex app-server` exited with an error: \(stderr)"
        case .requestTimedOut(let seconds, let stderr):
            return "`codex app-server` timed out after \(Int(seconds))s: \(stderr)"
        case .stdoutSetupFailed:
            return "Failed to configure the app-server output stream."
        case .stdoutReadFailed(let reason):
            return "Failed to read app-server output: \(reason)"
        case .missingResult:
            return "Missing result payload in app-server response."
        case .rpcError(let message):
            return "Codex app-server error: \(message)"
        }
    }
}
