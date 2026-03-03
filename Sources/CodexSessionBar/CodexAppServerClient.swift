import Darwin
import Foundation

actor CodexAppServerClient {
    private let jsonDecoder = JSONDecoder()
    private let requestTimeout: TimeInterval = 8

    func fetchActiveSessions() throws -> [ActiveSession] {
        guard let codexExecutable = resolveCodexExecutable() else {
            throw ClientError.codexNotFound
        }

        let session = try AppServerSession(codexExecutable: codexExecutable)
        defer { session.close() }

        var requestID = 1
        func nextRequestID() -> Int {
            defer { requestID += 1 }
            return requestID
        }

        let initializeResponse = try session.sendRequest(
            id: nextRequestID(),
            method: "initialize",
            params: InitializeParams(
                clientInfo: InitializeClientInfo(name: "codex-session-bar", title: "Codex Session Bar", version: "0.3.0"),
                capabilities: InitializeCapabilities(experimentalApi: true)
            ),
            timeout: requestTimeout
        )
        let _: InitializeResponse = try decodeResult(from: initializeResponse)

        var loadedIDs = Set<String>()
        var loadedCursor: String?
        while true {
            let response = try session.sendRequest(
                id: nextRequestID(),
                method: "thread/loaded/list",
                params: ThreadLoadedListParams(cursor: loadedCursor, limit: 250),
                timeout: requestTimeout
            )
            let page: ThreadLoadedListResponse = try decodeResult(from: response)
            loadedIDs.formUnion(page.data)

            guard let nextCursor = page.nextCursor, !nextCursor.isEmpty else {
                break
            }
            loadedCursor = nextCursor
        }

        var threads: [CodexThread] = []
        var threadCursor: String?
        while true {
            let response = try session.sendRequest(
                id: nextRequestID(),
                method: "thread/list",
                params: ThreadListParams(cursor: threadCursor, limit: 250, sortKey: "updated_at", archived: false),
                timeout: requestTimeout
            )
            let page: ThreadListResponse = try decodeResult(from: response)
            threads.append(contentsOf: page.data)

            guard let nextCursor = page.nextCursor, !nextCursor.isEmpty else {
                break
            }
            threadCursor = nextCursor
        }

        return Self.selectTrackedSessions(
            threads: threads,
            loadedIDs: loadedIDs,
            now: Date(),
            recentWindow: 24 * 60 * 60
        )
    }

    static func collectAllPages<T>(
        fetchPage: (String?) throws -> (data: [T], nextCursor: String?)
    ) rethrows -> [T] {
        var allItems: [T] = []
        var cursor: String? = nil

        while true {
            let page = try fetchPage(cursor)
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
        loadedIDs: Set<String>,
        now: Date,
        recentWindow: TimeInterval
    ) -> [ActiveSession] {
        let recentCutoff = now.addingTimeInterval(-recentWindow)

        let trackedThreads = threads.filter { thread in
            let isLoaded = loadedIDs.contains(thread.id)
            let updatedDate = Date(timeIntervalSince1970: thread.updatedAt)
            return isLoaded || updatedDate >= recentCutoff
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
                isLoaded: loadedIDs.contains(thread.id)
            )
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func decodeResult<T: Decodable>(from response: [String: Any]) throws -> T {
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            throw ClientError.rpcError(message)
        }

        guard let resultObject = response["result"] else {
            throw ClientError.missingResult
        }

        let resultData = try JSONSerialization.data(withJSONObject: resultObject)
        return try jsonDecoder.decode(T.self, from: resultData)
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
}

private final class AppServerSession {
    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let stdoutFD: Int32

    private var closed = false
    private var stdoutBuffer = Data()
    private var responseByID: [Int: [String: Any]] = [:]
    private var stderrCache = Data()
    private var didReadStderr = false

    init(codexExecutable: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutable)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ClientError.processLaunchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.stdoutFD = stdoutHandle.fileDescriptor

        let flags = fcntl(stdoutFD, F_GETFL)
        if flags == -1 || fcntl(stdoutFD, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw ClientError.stdoutSetupFailed
        }
    }

    deinit {
        close()
    }

    func close() {
        guard !closed else {
            return
        }

        closed = true

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        cacheStderr()

        try? stdinHandle.close()
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    func sendRequest<Params: Encodable>(
        id: Int,
        method: String,
        params: Params,
        timeout: TimeInterval
    ) throws -> [String: Any] {
        let request = RequestEnvelope(id: id, method: method, params: params)
        let payload = try JSONEncoder().encode(AnyEncodable(request))

        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))

        return try waitForResponse(id: id, timeout: timeout)
    }

    private func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let response = responseByID.removeValue(forKey: id) {
                return response
            }

            try pumpStdout()

            if !process.isRunning {
                try pumpStdout(flushRemainder: true)
                if let response = responseByID.removeValue(forKey: id) {
                    return response
                }

                let stderrText = cachedStderrText()
                throw ClientError.processFailed(stderrText)
            }

            Thread.sleep(forTimeInterval: 0.01)
        }

        process.terminate()
        process.waitUntilExit()
        let stderrText = cachedStderrText()
        throw ClientError.requestTimedOut(timeout, stderrText)
    }

    private func pumpStdout(flushRemainder: Bool = false) throws {
        var chunk = [UInt8](repeating: 0, count: 4096)

        while true {
            let readCount = Darwin.read(stdoutFD, &chunk, chunk.count)

            if readCount > 0 {
                stdoutBuffer.append(contentsOf: chunk.prefix(readCount))
                parseBufferedLines()
                continue
            }

            if readCount == 0 {
                if flushRemainder, !stdoutBuffer.isEmpty {
                    processLine(stdoutBuffer)
                    stdoutBuffer.removeAll(keepingCapacity: true)
                }
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            throw ClientError.stdoutReadFailed(String(cString: strerror(errno)))
        }
    }

    private func parseBufferedLines() {
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            var lineData = stdoutBuffer.prefix(upTo: newlineIndex)
            stdoutBuffer.removeSubrange(...newlineIndex)

            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }

            processLine(lineData)
        }
    }

    private func processLine(_ line: Data) {
        guard !line.isEmpty else {
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: line),
              let dictionary = object as? [String: Any],
              let id = parseRequestID(from: dictionary["id"])
        else {
            return
        }

        responseByID[id] = dictionary
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

    private func cacheStderr() {
        guard !didReadStderr else {
            return
        }

        didReadStderr = true
        let data = stderrHandle.readDataToEndOfFile()
        if !data.isEmpty {
            stderrCache.append(data)
        }
    }

    private func cachedStderrText() -> String {
        cacheStderr()

        let text = String(data: stderrCache, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : "Unknown app-server error"
    }
}

private struct RequestEnvelope<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params
}

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

private struct ThreadLoadedListParams: Encodable {
    let cursor: String?
    let limit: Int
}

private struct ThreadListParams: Encodable {
    let cursor: String?
    let limit: Int
    let sortKey: String
    let archived: Bool
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
