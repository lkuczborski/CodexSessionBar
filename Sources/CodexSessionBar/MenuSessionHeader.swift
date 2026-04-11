import SwiftUI

struct MenuSessionHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let workspace: String
    let statusLabel: String?
    let isLive: Bool
    let activeRoute: ChatWindowRoute
    let recentSessions: [SessionSummary]
    let chooseWorkingDirectory: () -> Void
    let createFreshSession: () -> Void
    let selectSession: (SessionSummary) -> Void
    let quit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineLimit(1)

                    if let statusLabel {
                        SessionBadge(
                            label: statusLabel,
                            tint: isLive ? Color.green.opacity(0.18) : AdaptivePalette.neutralBadgeTint(for: colorScheme)
                        )
                    }
                }

                Button(action: chooseWorkingDirectory) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .semibold))
                        Text(workspace)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                MiniToolbarButton(systemImage: "plus", action: createFreshSession)

                Menu {
                    if recentSessions.isEmpty {
                        Text("No recent sessions")
                    } else {
                        ForEach(recentSessions) { session in
                            Button {
                                selectSession(session)
                            } label: {
                                if activeRoute.threadID == session.id {
                                    Label(session.title, systemImage: "checkmark")
                                } else {
                                    Text(session.title)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("Quit", role: .destructive, action: quit)
                } label: {
                    MiniToolbarButtonLabel(systemImage: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }
}
