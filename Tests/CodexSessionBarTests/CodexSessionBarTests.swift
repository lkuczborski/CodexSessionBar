import Foundation
import XCTest
@testable import CodexSessionBar

final class CodexSessionBarTests: XCTestCase {
    func testSelectTrackedSessionsIncludesLoadedEvenIfOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = thread(id: "loaded-old", updatedAt: now.addingTimeInterval(-8 * 24 * 60 * 60).timeIntervalSince1970)

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [stale],
            loadedIDs: ["loaded-old"],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "loaded-old")
        XCTAssertTrue(sessions[0].isLoaded)
    }

    func testSelectTrackedSessionsIncludesRecentAndExcludesOldUnloaded() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = thread(id: "recent", updatedAt: now.addingTimeInterval(-2 * 60 * 60).timeIntervalSince1970)
        let old = thread(id: "old", updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60).timeIntervalSince1970)

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [old, recent],
            loadedIDs: [],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "recent")
        XCTAssertFalse(sessions[0].isLoaded)
    }

    func testSelectTrackedSessionsReturnsEmptyWhenNothingLoadedOrRecent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = thread(id: "old", updatedAt: now.addingTimeInterval(-9 * 24 * 60 * 60).timeIntervalSince1970)

        let sessions = CodexAppServerClient.selectTrackedSessions(
            threads: [old],
            loadedIDs: [],
            now: now,
            recentWindow: 24 * 60 * 60
        )

        XCTAssertTrue(sessions.isEmpty)
    }

    func testCollectAllPagesTraversesCursors() {
        var seenCursors: [String?] = []

        let collected = CodexAppServerClient.collectAllPages { cursor in
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

    func testCollectAllPagesStopsOnEmptyCursor() {
        var calls = 0

        let collected = CodexAppServerClient.collectAllPages { _ in
            calls += 1
            return (data: [1, 2], nextCursor: "")
        }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(collected, [1, 2])
    }

    private func thread(id: String, updatedAt: TimeInterval) -> CodexThread {
        CodexThread(
            id: id,
            preview: "Preview \(id)",
            modelProvider: "openai",
            createdAt: updatedAt - 300,
            updatedAt: updatedAt,
            status: nil,
            path: nil,
            cwd: "/tmp",
            source: .cli
        )
    }
}
