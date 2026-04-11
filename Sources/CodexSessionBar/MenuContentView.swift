import SwiftUI

struct MenuLaunchpadView: View {
    let model: CodexMiniAppModel

    var body: some View {
        MenuSessionPanel(
            model: model.activeSessionModel,
            activeRoute: model.displayedSessionRoute,
            recentSessions: model.recentSwitcherSessions,
            createFreshSession: model.createFreshSession,
            selectSession: { session in
                model.selectSession(.thread(session.id))
            },
            quit: SystemCommandRunner.quit
        )
        .frame(width: 480, height: 720)
        .background(AuroraBackdrop())
    }
}
