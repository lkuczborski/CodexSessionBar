import Foundation
import XCTest
@testable import CodexSessionBar

final class CodexSessionBarTests: XCTestCase {
    func testSelectTrackedSessionsIncludesLiveEvenIfOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = thread(
            id: "live-old",
            updatedAt: now.addingTimeInterval(-8 * 24 * 60 * 60).timeIntervalSince1970,
            status: ThreadStatus(type: .idle)
        )

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [stale],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "live-old")
        XCTAssertTrue(sessions[0].isLive)
    }

    func testSelectTrackedSessionsIncludesRecentStoredAndExcludesOldStored() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = thread(
            id: "recent",
            updatedAt: now.addingTimeInterval(-2 * 60 * 60).timeIntervalSince1970,
            status: .notLoaded
        )
        let old = thread(
            id: "old",
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60).timeIntervalSince1970,
            status: .notLoaded
        )

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [old, recent],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "recent")
        XCTAssertFalse(sessions[0].isLive)
    }

    func testSelectTrackedSessionsReturnsEmptyWhenNothingLiveOrRecent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = thread(
            id: "old",
            updatedAt: now.addingTimeInterval(-9 * 24 * 60 * 60).timeIntervalSince1970,
            status: .notLoaded
        )

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [old],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertTrue(sessions.isEmpty)
    }

    func testCollectAllPagesTraversesCursors() async throws {
        var seenCursors: [String?] = []

        let collected = await CodexAppServerClient.collectAllPages { cursor in
            seenCursors.append(cursor)

            switch cursor {
            case nil:
                return (data: ["a", "b"], nextCursor: "cursor-1")
            case "cursor-1":
                return (data: ["c"], nextCursor: "cursor-2")
            case "cursor-2":
                return (data: ["d"], nextCursor: nil)
            default:
                XCTFail("Unexpected cursor \(String(describing: cursor))")
                return (data: [], nextCursor: nil)
            }
        }

        XCTAssertEqual(collected, ["a", "b", "c", "d"])
        XCTAssertEqual(seenCursors.count, 3)
        XCTAssertNil(seenCursors[0])
        XCTAssertEqual(seenCursors[1], "cursor-1")
        XCTAssertEqual(seenCursors[2], "cursor-2")
    }

    func testCollectAllPagesStopsOnEmptyCursor() async throws {
        var calls = 0

        let collected = await CodexAppServerClient.collectAllPages { _ in
            calls += 1
            return (data: [1, 2], nextCursor: "")
        }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(collected, [1, 2])
    }

    func testThreadListFilterValuesExcludeUnknown() {
        XCTAssertFalse(SessionSourceKind.threadListFilterValues.contains(.unknown))
        XCTAssertTrue(SessionSourceKind.threadListFilterValues.contains(.cli))
        XCTAssertTrue(SessionSourceKind.threadListFilterValues.contains(.appServer))
    }

    func testAppServerEventMapsThreadAndTurnNotificationsToRefreshes() {
        XCTAssertEqual(AppServerEvent(method: "thread/status/changed"), .sessionsChanged(reason: "thread/status/changed"))
        XCTAssertEqual(AppServerEvent(method: "turn/completed"), .sessionsChanged(reason: "turn/completed"))
        XCTAssertNil(AppServerEvent(method: "item/agentMessage/delta"))
    }

    func testSessionSourceKindDecodesLegacySubAgentObject() throws {
        let data = Data(#"{"subAgent":"review"}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionSourceKind.self, from: data)
        XCTAssertEqual(decoded, .subAgentReview)
    }

    private func thread(id: String, updatedAt: TimeInterval, status: ThreadStatus) -> CodexThread {
        CodexThread(
            id: id,
            preview: "Preview \(id)",
            modelProvider: "openai",
            createdAt: updatedAt - 300,
            updatedAt: updatedAt,
            status: status,
            path: nil,
            cwd: "/tmp",
            source: .cli
        )
    }
}
