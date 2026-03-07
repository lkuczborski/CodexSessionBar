import SwiftUI

struct TrackerWindowView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No Tracked Sessions",
                    systemImage: "terminal",
                    description: Text("Start or resume a Codex session and refresh; recent sessions will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.sessions) { session in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.displayTitle)
                                .font(.headline)
                                .lineLimit(2)

                            Text(session.cwd.isEmpty ? "Unknown working directory" : session.cwd)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                sessionTag(title: session.activityLabel, color: session.isLive ? .green.opacity(0.2) : .gray.opacity(0.14))
                                sessionTag(title: session.sourceLabel)

                                if !session.modelProvider.isEmpty {
                                    sessionTag(title: session.modelProvider)
                                }

                                sessionTag(title: "Created \(session.createdRelative)")
                                sessionTag(title: "Updated \(session.updatedRelative)")
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Button("Open Directory") {
                                store.openWorkingDirectory(session)
                            }
                            .disabled(session.cwd.isEmpty)

                            Button("Copy Session ID") {
                                store.copySessionID(session)
                            }

                            Button("Reveal Session File") {
                                store.revealThreadPath(session)
                            }
                            .disabled(session.path == nil)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
        .task {
            store.startIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Codex Sessions")
                .font(.title2.weight(.semibold))

            HStack {
                Text(store.statusText)
                    .foregroundStyle(.secondary)

                Spacer()

                if let refreshDate = store.lastRefresh {
                    Text("Last refresh: \(refreshDate.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
    }

    private func sessionTag(title: String, color: Color = .gray.opacity(0.14)) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}
