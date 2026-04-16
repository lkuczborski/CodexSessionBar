import SwiftUI

struct MiniTranscriptView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entries: [ConversationEntry]

    @State private var searchText = ""
    @State private var collapsedEntryIDs: Set<String> = []
    @State private var initializedEntryIDs: Set<String> = []

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                transcriptToolbar(using: proxy)
                    .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text(emptyStateMessage)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(filteredEntries) { entry in
                                MiniTranscriptEntryView(
                                    entry: entry,
                                    isCollapsed: collapsedEntryIDs.contains(entry.id),
                                    toggleCollapse: entry.canCollapseInTranscript ? {
                                        toggleCollapse(for: entry.id)
                                    } : nil
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
                        .padding(.vertical, LayoutMetrics.transcriptVerticalInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .task(id: entries.last?.id) {
                await scrollToLatestMessage(using: proxy)
            }
            .task {
                synchronizeCollapseState()
            }
            .onChange(of: entries.map(\.id)) { _, _ in
                synchronizeCollapseState()
            }
        }
    }

    @MainActor
    private func scrollToLatestMessage(using proxy: ScrollViewProxy) async {
        guard let lastEntry = filteredEntries.last else {
            return
        }

        // Let layout settle so launch-time transcript hydration can scroll reliably.
        try? await Task.sleep(for: .milliseconds(40))

        if lastEntry.isStreaming {
            proxy.scrollTo(lastEntry.id, anchor: .bottom)
        } else {
            withAnimation(.snappy(duration: 0.26)) {
                proxy.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func transcriptToolbar(using proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Search transcript", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(transcriptToolbarFill, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(transcriptToolbarStroke, lineWidth: 1)
                }

                Spacer(minLength: 0)

                transcriptJumpButton(
                    title: "You",
                    systemImage: "arrow.down.to.line",
                    isEnabled: latestUserEntry != nil
                ) {
                    scrollToLatest(kind: .user, using: proxy)
                }

                transcriptJumpButton(
                    title: "Codex",
                    systemImage: "sparkles",
                    isEnabled: latestAssistantEntry != nil
                ) {
                    scrollToLatest(kind: .assistant, using: proxy)
                }
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(searchSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func transcriptJumpButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help("Jump to latest \(title) entry")
    }

    private var filteredEntries: [ConversationEntry] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return entries
        }

        return entries.filter { $0.matches(searchQuery: trimmedQuery) }
    }

    private var latestUserEntry: ConversationEntry? {
        filteredEntries.last(where: { $0.kind == .user })
    }

    private var latestAssistantEntry: ConversationEntry? {
        filteredEntries.last(where: { $0.kind == .assistant })
    }

    private var emptyStateMessage: String {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return "This conversation is still getting started."
        }

        return "Nothing in this thread matches “\(trimmedQuery)”."
    }

    private var searchSummary: String {
        let resultLabel = filteredEntries.count == 1 ? "1 result" : "\(filteredEntries.count) results"
        return "\(resultLabel) in this thread"
    }

    private var transcriptToolbarFill: Color {
        AdaptivePalette.chromeFill(for: colorScheme)
    }

    private var transcriptToolbarStroke: Color {
        AdaptivePalette.chromeStroke(for: colorScheme)
    }

    private func toggleCollapse(for entryID: String) {
        if collapsedEntryIDs.contains(entryID) {
            collapsedEntryIDs.remove(entryID)
        } else {
            collapsedEntryIDs.insert(entryID)
        }
    }

    private func synchronizeCollapseState() {
        let currentIDs = Set(entries.map(\.id))
        collapsedEntryIDs = collapsedEntryIDs.filter { currentIDs.contains($0) }
        initializedEntryIDs = initializedEntryIDs.filter { currentIDs.contains($0) }

        for entry in entries where !initializedEntryIDs.contains(entry.id) {
            if entry.canCollapseInTranscript {
                collapsedEntryIDs.insert(entry.id)
            }
            initializedEntryIDs.insert(entry.id)
        }
    }

    private func scrollToLatest(kind: ConversationEntry.Kind, using proxy: ScrollViewProxy) {
        guard let target = filteredEntries.last(where: { $0.kind == kind }) else {
            return
        }

        withAnimation(.snappy(duration: 0.22)) {
            proxy.scrollTo(target.id, anchor: .center)
        }
    }
}
