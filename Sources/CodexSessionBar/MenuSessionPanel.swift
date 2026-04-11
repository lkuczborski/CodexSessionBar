import SwiftUI
import UniformTypeIdentifiers

struct MenuSessionPanel: View {
    @Bindable var model: ChatWindowModel
    let activeRoute: ChatWindowRoute
    let recentSessions: [SessionSummary]
    let createFreshSession: () -> Void
    let selectSession: (SessionSummary) -> Void
    let quit: () -> Void

    @Namespace private var composerFocusNamespace
    @FocusState private var composerFocused: Bool
    @State private var isChoosingWorkingDirectory = false

    var body: some View {
        VStack(spacing: 0) {
            MenuSessionHeader(
                title: model.title,
                workspace: model.subtitle,
                statusLabel: model.statusBadgeLabel,
                isLive: model.summary?.isLive ?? false,
                activeRoute: activeRoute,
                recentSessions: recentSessions,
                chooseWorkingDirectory: { isChoosingWorkingDirectory = true },
                createFreshSession: createFreshSession,
                selectSession: selectSession,
                quit: quit
            )

            if let banner = model.banner {
                MiniSessionBanner(banner: banner)
                    .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
                    .padding(.bottom, 14)
            }

            WindowHairline()

            MiniTranscriptView(entries: model.visibleConversation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            WindowHairline()

            MiniSessionComposer(
                draftText: $model.draftText,
                selectedModel: $model.selectedModel,
                selectedReasoningEffort: $model.selectedReasoningEffort,
                fastModeEnabled: $model.fastModeEnabled,
                availableModels: model.availableModels,
                selectedModelDetails: model.selectedCodexModel,
                availableReasoningEfforts: model.availableReasoningEfforts,
                isLoadingModels: model.isLoadingModels,
                isSending: model.isSending,
                composerFocusNamespace: composerFocusNamespace,
                composerFocused: $composerFocused,
                sendMessage: model.sendMessage
            )
        }
        .background(MiniSessionBackdrop())
        .focusScope(composerFocusNamespace)
        .fileImporter(isPresented: $isChoosingWorkingDirectory, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else {
                return
            }

            model.updateWorkingDirectory(url.path)
        }
        .task {
            await focusComposerSoon()
        }
        .onChange(of: model.isSending) { _, isSending in
            if !isSending {
                Task {
                    await focusComposerSoon()
                }
            }
        }
    }

    @MainActor
    private func focusComposerSoon() async {
        try? await Task.sleep(for: .milliseconds(120))
        composerFocused = true
    }
}
