import Foundation
import XCTest
@testable import CodexSessionBar

final class CodexSessionBarTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
    }

    func testSessionSummaryUsesNameBeforePreview() {
        let thread = makeThread(
            id: "named",
            preview: "Fallback preview",
            name: "Named session",
            turns: []
        )

        XCTAssertEqual(thread.sessionSummary.title, "Named session")
    }

    func testSessionSummarySearchMatchesMultipleFields() {
        let summary = makeThread(
            id: "thread-123",
            preview: "Investigate menu bar behavior",
            name: "Menu audit",
            turns: []
        ).sessionSummary

        XCTAssertTrue(summary.matches(searchQuery: "audit"))
        XCTAssertTrue(summary.matches(searchQuery: "thread-123"))
        XCTAssertTrue(summary.matches(searchQuery: "main"))
        XCTAssertFalse(summary.matches(searchQuery: "android"))
    }

    func testThreadListFilterValuesCoverInteractiveSources() {
        XCTAssertTrue(SessionSourceKind.threadListFilterValues.contains(.cli))
        XCTAssertTrue(SessionSourceKind.threadListFilterValues.contains(.appServer))
        XCTAssertTrue(SessionSourceKind.threadListFilterValues.contains(.subAgent(.generic)))
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

    func testSessionRecordBuildsConversationFromThreadItems() {
        let turn = CodexTurn(
            id: "turn-1",
            items: [
                .userMessage(ThreadUserMessageItem(id: "u1", content: [.text("Build a menu bar app")])),
                .agentMessage(ThreadAgentMessageItem(id: "a1", text: "I can help with that.")),
                .commandExecution(
                    ThreadCommandExecutionItem(
                        id: "c1",
                        command: "swift build",
                        cwd: "/tmp/project",
                        status: .completed,
                        aggregatedOutput: "Build complete",
                        exitCode: 0
                    )
                )
            ],
            status: .completed,
            error: nil
        )

        let record = makeThread(id: "thread-1", preview: "Build a menu bar app", name: nil, turns: [turn]).sessionRecord

        XCTAssertEqual(record.conversation.map(\.kind), [.user, .assistant, .tool])
        XCTAssertEqual(record.conversation[0].body, "Build a menu bar app")
        XCTAssertEqual(record.conversation[1].body, "I can help with that.")
        XCTAssertEqual(record.conversation[2].title, "$ swift build")
    }

    func testThreadRecordDecodesCurrentFileChangeKindShape() throws {
        let payload = """
        {
          "thread": {
            "id": "thread-live",
            "preview": "Debug selector",
            "ephemeral": false,
            "modelProvider": "openai",
            "createdAt": 1000000,
            "updatedAt": 1000360,
            "status": { "type": "notLoaded" },
            "path": null,
            "cwd": "/tmp/project",
            "cliVersion": "1.0.0",
            "source": "cli",
            "agentNickname": null,
            "agentRole": null,
            "gitInfo": { "sha": null, "branch": "main", "originUrl": null },
            "name": "Live thread",
            "turns": [
              {
                "id": "turn-1",
                "status": "completed",
                "error": null,
                "items": [
                  {
                    "type": "userMessage",
                    "id": "item-1",
                    "content": [
                      { "type": "text", "text": "hello", "text_elements": [] }
                    ]
                  },
                  {
                    "type": "fileChange",
                    "id": "item-2",
                    "changes": [
                      {
                        "path": "/tmp/project/file.swift",
                        "kind": { "type": "update", "move_path": null },
                        "diff": "@@"
                      }
                    ],
                    "status": "completed"
                  },
                  {
                    "type": "agentMessage",
                    "id": "item-3",
                    "text": "world"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ThreadReadResponse.self, from: payload)
        let conversation = response.thread.sessionRecord.conversation

        XCTAssertEqual(conversation.map(\.kind), [.user, .tool, .assistant])
        XCTAssertEqual(conversation[0].body, "hello")
        XCTAssertEqual(conversation[1].title, "File changes")
        XCTAssertEqual(conversation[2].body, "world")
    }

    func testTurnDecodingSkipsMalformedItemsInsteadOfDroppingWholeTurn() throws {
        let payload = """
        {
          "id": "turn-1",
          "status": "completed",
          "error": null,
          "items": [
            {
              "type": "userMessage",
              "id": "item-1",
              "content": [
                { "type": "text", "text": "before", "text_elements": [] }
              ]
            },
            {
              "type": "fileChange",
              "id": "item-bad",
              "changes": "not-an-array",
              "status": "completed"
            },
            {
              "type": "agentMessage",
              "id": "item-2",
              "text": "after"
            }
          ]
        }
        """.data(using: .utf8)!

        let turn = try JSONDecoder().decode(CodexTurn.self, from: payload)
        let conversation = turn.conversationEntries

        XCTAssertEqual(conversation.map(\.kind), [.user, .assistant])
        XCTAssertEqual(conversation[0].body, "before")
        XCTAssertEqual(conversation[1].body, "after")
    }

    func testChatWindowRouteParsesThreadIdentifier() {
        let route = ChatWindowRoute.thread("thread-123")
        XCTAssertEqual(route.threadID, "thread-123")
        XCTAssertTrue(ChatWindowRoute.draft().threadID == nil)
    }

    func testConversationEntrySearchMatchesBodyTitleAndFootnote() {
        let entry = ConversationEntry(
            id: "tool-1",
            kind: .tool,
            title: "$ swift test",
            body: "Executed unit tests for the mini transcript",
            footnote: "Completed • /tmp/project",
            isStreaming: false
        )

        XCTAssertTrue(entry.matches(searchQuery: "swift test"))
        XCTAssertTrue(entry.matches(searchQuery: "mini transcript"))
        XCTAssertTrue(entry.matches(searchQuery: "/tmp/project"))
        XCTAssertFalse(entry.matches(searchQuery: "archive window"))
    }

    func testConversationEntryCopyPayloadIncludesContextualMetadata() {
        let entry = ConversationEntry(
            id: "plan-1",
            kind: .plan,
            title: "Plan",
            body: "Add jump buttons and search.",
            footnote: "2 steps",
            isStreaming: false
        )

        XCTAssertEqual(entry.copyPayload, "Plan\n\nAdd jump buttons and search.\n\n2 steps")
    }

    func testConversationEntryDefaultCollapseTargetsToolEntries() {
        let toolEntry = ConversationEntry(
            id: "tool-1",
            kind: .tool,
            title: "$ swift build",
            body: """
            [0/1] Planning build
            [1/1] Build complete
            Finished in 0.2s
            """,
            footnote: "Completed",
            isStreaming: false
        )
        let assistantEntry = ConversationEntry(
            id: "assistant-1",
            kind: .assistant,
            title: "Codex",
            body: "Ready.",
            footnote: nil,
            isStreaming: false
        )

        XCTAssertTrue(toolEntry.defaultTranscriptCollapsed)
        XCTAssertFalse(assistantEntry.defaultTranscriptCollapsed)
    }

    func testConversationEntryShortToolOutputDoesNotCollapse() {
        let shortToolEntry = ConversationEntry(
            id: "tool-short",
            kind: .tool,
            title: "$ swift test",
            body: """
            [0/1] Planning build
            Build complete!
            """,
            footnote: "Completed",
            isStreaming: false
        )

        XCTAssertFalse(shortToolEntry.canCollapseInTranscript)
        XCTAssertFalse(shortToolEntry.defaultTranscriptCollapsed)
    }

    func testTranscriptBodyParserSplitsFencedCodeBlocks() {
        let body = """
        Here is Swift:

        ```swift
        let value = 3
        print(value)
        ```

        Done.
        """

        XCTAssertEqual(
            TranscriptBodyParser.segments(from: body),
            [
                .text("Here is Swift:\n"),
                .code(languageHint: "swift", code: "let value = 3\nprint(value)"),
                .text("\nDone.")
            ]
        )
    }

    func testTranscriptBodyParserLeavesDanglingFenceAsText() {
        let body = """
        ```python
        print("hi")
        """

        XCTAssertEqual(
            TranscriptBodyParser.segments(from: body),
            [.text("``` python\nprint(\"hi\")")]
        )
    }

    func testTranscriptCodeLanguageRecognizesCommonAliases() {
        XCTAssertEqual(TranscriptCodeLanguage(hint: "py"), .python)
        XCTAssertEqual(TranscriptCodeLanguage(hint: "tsx"), .typescript)
        XCTAssertEqual(TranscriptCodeLanguage(hint: "zsh"), .shell)
        XCTAssertEqual(TranscriptCodeLanguage(hint: "yml"), .yaml)
        XCTAssertNil(TranscriptCodeLanguage(hint: "ruby"))
    }

    func testTranscriptCodeDetectorInfersLanguageFromCommandTitlePath() {
        let hint = TranscriptCodeDetector.inferLanguageHint(
            preferredHint: nil,
            title: "$ /bin/zsh -lc \"nl -ba Sources/CodexSessionBar/TranscriptBodyView.swift\"",
            body: "1  import Foundation\n2  import SwiftUI"
        )

        XCTAssertEqual(hint, "swift")
    }

    func testTranscriptCodeDetectorTreatsNumberedSourceOutputAsCode() {
        let body = """
        1  import Foundation
        2  import SwiftUI
        3
        4  enum TranscriptBodySegment: Equatable, Sendable {
        5      case text(String)
        6      case code(languageHint: String?, code: String)
        7  }
        """

        XCTAssertTrue(
            TranscriptCodeDetector.shouldRenderAsCode(
                body,
                preferredLanguageHint: "swift"
            )
        )
    }

    func testTranscriptMarkdownRendererPreservesLinks() {
        let rendered = TranscriptMarkdownRenderer.attributedText(
            from: "Open [docs](https://example.com/docs)"
        )

        let linkRuns = rendered.runs.compactMap { run -> URL? in
            run.link
        }

        XCTAssertEqual(linkRuns, [URL(string: "https://example.com/docs")!])
    }

    func testTranscriptMarkdownRendererMarksInlineCode() {
        let rendered = TranscriptMarkdownRenderer.attributedText(
            from: "Use `swift test` here."
        )

        let hasCodeRun = rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains(.code) == true
        }

        XCTAssertTrue(hasCodeRun)
    }

    @MainActor
    func testDisplayedSessionRoutePreservesSelectedThread() {
        let model = CodexMiniAppModel(autostart: false)
        let older = makeThread(
            id: "thread-older",
            preview: "Older preview",
            name: "Older",
            turns: []
        ).sessionSummary
        let newer = makeThread(
            id: "thread-newer",
            preview: "Newer preview",
            name: "Newer",
            turns: []
        ).sessionSummary

        model.merge(summary: older)
        model.merge(summary: newer)
        model.selectSession(.thread(older.id))

        XCTAssertEqual(model.displayedSessionRoute.threadID, older.id)

        model.merge(summary: newer)

        XCTAssertEqual(model.displayedSessionRoute.threadID, older.id)
    }

    @MainActor
    func testDisplayedSessionRoutePreservesDraftSelection() {
        let model = CodexMiniAppModel(autostart: false)
        let session = makeThread(
            id: "thread-1",
            preview: "Session preview",
            name: "Session",
            turns: []
        ).sessionSummary

        model.merge(summary: session)
        model.createFreshSession()

        XCTAssertNil(model.displayedSessionRoute.threadID)
    }

    func testThreadHydrationNeededWhenNoCachedSummaryExists() {
        let latestSummary = makeThread(
            id: "thread-1",
            preview: "Session preview",
            name: "Session",
            turns: []
        ).sessionSummary

        XCTAssertTrue(
            CodexMiniAppModel.shouldHydrateThreadRecord(
                cachedSummary: nil,
                latestSummary: latestSummary
            )
        )
    }

    func testThreadHydrationNeededWhenCachedSummaryIsStale() {
        let staleSummary = makeThread(
            id: "thread-1",
            preview: "Older preview",
            name: "Session",
            turns: []
        ).sessionSummary
        let latestSummary = SessionSummary(
            id: staleSummary.id,
            name: staleSummary.name,
            preview: staleSummary.preview,
            cwd: staleSummary.cwd,
            path: staleSummary.path,
            modelProvider: staleSummary.modelProvider,
            source: staleSummary.source,
            createdAt: staleSummary.createdAt,
            updatedAt: staleSummary.updatedAt.addingTimeInterval(60),
            status: staleSummary.status,
            isEphemeral: staleSummary.isEphemeral,
            agentNickname: staleSummary.agentNickname,
            agentRole: staleSummary.agentRole,
            gitBranch: staleSummary.gitBranch
        )

        XCTAssertTrue(
            CodexMiniAppModel.shouldHydrateThreadRecord(
                cachedSummary: staleSummary,
                latestSummary: latestSummary
            )
        )
    }

    func testThreadHydrationSkippedWhenCachedSummaryMatchesLatestSummary() {
        let latestSummary = makeThread(
            id: "thread-1",
            preview: "Session preview",
            name: "Session",
            turns: []
        ).sessionSummary

        XCTAssertFalse(
            CodexMiniAppModel.shouldHydrateThreadRecord(
                cachedSummary: latestSummary,
                latestSummary: latestSummary
            )
        )
    }

    @MainActor
    func testComposerPreferencesRoundTripSelections() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        ComposerPreferences.setSelectedModel("gpt-5.4", in: defaults)
        ComposerPreferences.setSelectedReasoningEffort(.xhigh, in: defaults)
        ComposerPreferences.setFastModeEnabled(true, in: defaults)

        XCTAssertEqual(ComposerPreferences.selectedModel(in: defaults), "gpt-5.4")
        XCTAssertEqual(ComposerPreferences.selectedReasoningEffort(in: defaults), .xhigh)
        XCTAssertTrue(ComposerPreferences.fastModeEnabled(in: defaults))
    }

    @MainActor
    func testComposerPreferencesClearSelections() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        ComposerPreferences.setSelectedModel("gpt-5.4", in: defaults)
        ComposerPreferences.setSelectedReasoningEffort(.high, in: defaults)
        ComposerPreferences.setSelectedModel(nil, in: defaults)
        ComposerPreferences.setSelectedReasoningEffort(nil, in: defaults)

        XCTAssertNil(ComposerPreferences.selectedModel(in: defaults))
        XCTAssertNil(ComposerPreferences.selectedReasoningEffort(in: defaults))
    }

    private func makeThread(
        id: String,
        preview: String,
        name: String?,
        turns: [CodexTurn]
    ) -> CodexThread {
        CodexThread(
            id: id,
            preview: preview,
            ephemeral: false,
            modelProvider: "openai",
            createdAt: 1_000_000,
            updatedAt: 1_000_360,
            status: .idle,
            path: nil,
            cwd: "/tmp/project",
            cliVersion: "1.0.0",
            source: .cli,
            agentNickname: nil,
            agentRole: nil,
            gitInfo: GitInfo(sha: nil, branch: "main", originUrl: nil),
            name: name,
            turns: turns
        )
    }
}
