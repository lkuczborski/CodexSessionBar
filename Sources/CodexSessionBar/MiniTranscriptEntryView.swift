import SwiftUI

struct MiniTranscriptEntryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: ConversationEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if entry.kind == .user {
                Spacer(minLength: LayoutMetrics.messageOpposingSpacer)
            }

            VStack(alignment: contentAlignment, spacing: 8) {
                if showsLabel {
                    Text(entry.title)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text(entry.body)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .lineSpacing(4)
                    .multilineTextAlignment(textAlignment)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote = entry.footnote {
                    Text(footnote)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(textAlignment)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if entry.isStreaming {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Thinking")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, entry.kind == .user ? LayoutMetrics.inlineTrailingInset : LayoutMetrics.inlineLeadingInset)
            .padding(.trailing, entry.kind == .user ? LayoutMetrics.inlineLeadingInset : LayoutMetrics.inlineTrailingInset)
            .padding(.vertical, 6)
            .frame(maxWidth: LayoutMetrics.messageMaxWidth, alignment: frameAlignment)

            if entry.kind != .user {
                Spacer(minLength: LayoutMetrics.messageOpposingSpacer)
            }
        }
    }

    private var showsLabel: Bool {
        switch entry.kind {
        case .user, .assistant:
            false
        case .plan, .tool, .notice:
            true
        }
    }

    private var font: Font {
        switch entry.kind {
        case .tool:
            .system(.caption, design: .monospaced)
        case .plan:
            .system(.body, design: .rounded).weight(.medium)
        case .user, .assistant, .notice:
            .system(.body, design: .rounded)
        }
    }

    private var foregroundStyle: Color {
        switch entry.kind {
        case .notice:
            .secondary
        case .tool:
            .primary.opacity(colorScheme == .dark ? 0.78 : 0.72)
        case .user, .assistant, .plan:
            .primary.opacity(colorScheme == .dark ? 0.94 : 0.88)
        }
    }

    private var contentAlignment: HorizontalAlignment {
        entry.kind == .user ? .trailing : .leading
    }

    private var frameAlignment: Alignment {
        entry.kind == .user ? .trailing : .leading
    }

    private var textAlignment: TextAlignment {
        entry.kind == .user ? .trailing : .leading
    }
}
