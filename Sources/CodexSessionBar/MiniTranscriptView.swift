import SwiftUI

struct MiniTranscriptView: View {
    let entries: [ConversationEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(entries) { entry in
                        MiniTranscriptEntryView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
                .padding(.vertical, LayoutMetrics.transcriptVerticalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task(id: entries.last?.id) {
                await scrollToLatestMessage(using: proxy)
            }
        }
    }

    @MainActor
    private func scrollToLatestMessage(using proxy: ScrollViewProxy) async {
        guard let lastEntry = entries.last else {
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
}
