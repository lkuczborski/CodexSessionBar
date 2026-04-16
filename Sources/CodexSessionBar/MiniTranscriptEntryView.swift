import AppKit
import SwiftUI

struct MiniTranscriptEntryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    let entry: ConversationEntry
    let isCollapsed: Bool
    let toggleCollapse: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if entry.kind == .user {
                Spacer(minLength: LayoutMetrics.messageOpposingSpacer)
            }

            VStack(alignment: contentAlignment, spacing: 8) {
                headerRow

                contentArea
            }
            .padding(.leading, horizontalInsetLeading)
            .padding(.trailing, horizontalInsetTrailing)
            .padding(.vertical, 6)
            .frame(maxWidth: rowContentMaxWidth, alignment: frameAlignment)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(copyFlashColor)
                    .padding(.vertical, -4)
            }
            .overlay(alignment: copyFeedbackAlignment) {
                if copied {
                    CopyFeedbackBadge()
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.spring(duration: 0.24, bounce: 0.22), value: copied)

        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if entry.showsTranscriptTitle {
                Text(entry.title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
            } else if entry.kind == .user {
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let toggleCollapse {
                    TranscriptEntryActionButton(
                        systemImage: isCollapsed ? "chevron.down" : "chevron.up",
                        helpText: isCollapsed ? "Expand block" : "Collapse block",
                        action: {
                            withAnimation(.snappy(duration: 0.18)) {
                                toggleCollapse()
                            }
                        }
                    )
                }

                if !copiesFromContentTap {
                    TranscriptEntryActionButton(
                        systemImage: copied ? "checkmark" : "doc.on.doc",
                        helpText: copied ? "Copied" : "Copy block",
                        action: copyEntry
                    )
                }
            }
            .opacity(isHovered || copied || toggleCollapse != nil ? 1 : 0)
            .animation(.easeInOut(duration: 0.16), value: isHovered)
            .animation(.easeInOut(duration: 0.16), value: copied)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        VStack(alignment: contentAlignment, spacing: 8) {
            if !isCollapsed {
                TranscriptBodyView(
                    text: entry.body,
                    font: font,
                    foregroundColor: foregroundStyle,
                    textAlignment: textAlignment,
                    frameAlignment: frameAlignment,
                    displayMode: transcriptBodyDisplayMode
                )
            } else {
                Text(entry.transcriptPreview)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .contentShape(Rectangle())
        .onTapGesture {
            guard copiesFromContentTap else {
                return
            }

            copyEntry()
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

    private var horizontalInsetLeading: CGFloat {
        entry.kind == .user ? LayoutMetrics.inlineTrailingInset : LayoutMetrics.inlineLeadingInset
    }

    private var horizontalInsetTrailing: CGFloat {
        entry.kind == .user ? LayoutMetrics.inlineLeadingInset : LayoutMetrics.inlineLeadingInset
    }

    private var rowContentMaxWidth: CGFloat? {
        entry.kind == .user ? LayoutMetrics.messageMaxWidth : .infinity
    }

    private func copyEntry() {
        guard !entry.isStreaming else {
            return
        }

        copyResetTask?.cancel()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.copyPayload, forType: .string)
        withAnimation(.spring(duration: 0.22, bounce: 0.28)) {
            copied = true
        }

        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.22)) {
                copied = false
            }
        }
    }

    private var copiesFromContentTap: Bool {
        !entry.isStreaming
    }

    private var copyFlashColor: Color {
        copied ? .accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12) : .clear
    }

    private var copyFeedbackAlignment: Alignment {
        entry.kind == .user ? .topTrailing : .topLeading
    }

    private var transcriptBodyDisplayMode: TranscriptBodyDisplayMode {
        guard entry.kind == .tool else {
            return .prose
        }

        return .automaticCode(
            languageHint: TranscriptCodeDetector.inferLanguageHint(
                preferredHint: nil,
                title: entry.title,
                body: entry.body
            )
        )
    }
}

private struct TranscriptEntryActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(AdaptivePalette.chromeFill(for: colorScheme), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(AdaptivePalette.chromeStroke(for: colorScheme), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

private struct CopyFeedbackBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label("Copied", systemImage: "checkmark")
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AdaptivePalette.controlFill(for: colorScheme), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(AdaptivePalette.controlStroke(for: colorScheme), lineWidth: 1)
            }
            .padding(.top, -8)
    }
}
