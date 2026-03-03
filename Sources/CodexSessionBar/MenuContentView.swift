import SwiftUI

struct MenuContentView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.sessions.isEmpty {
                Text("No tracked Codex sessions found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.sessions.prefix(8)) { session in
                            sessionRow(session)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await store.refreshNow() }
                }
                .disabled(store.isRefreshing)

                Button("Tracker Window") {
                    openWindow(id: "tracker")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Codex Session Tracker")
                .font(.headline)

            HStack {
                Text(store.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let lastRefresh = store.lastRefresh {
                    Text(lastRefresh.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: ActiveSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(session.cwd.isEmpty ? "Unknown working directory" : session.cwd)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack {
                Text(session.sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("• \(session.activityLabel)")
                    .font(.caption2)
                    .foregroundStyle(session.isLoaded ? .green : .secondary)

                Spacer()

                Text("Updated \(session.updatedRelative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Open Dir") {
                    store.openWorkingDirectory(session)
                }
                .disabled(session.cwd.isEmpty)

                Button("Copy ID") {
                    store.copySessionID(session)
                }

                Button("Reveal") {
                    store.revealThreadPath(session)
                }
                .disabled(session.path == nil)
            }
            .font(.caption)
            .buttonStyle(.link)
        }
    }
}
