import SwiftUI

@main
struct CodexSessionBarApp: App {
    @State private var model = CodexMiniAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuLaunchpadView(model: model)
        } label: {
            CodexMenuBarLabel(
                title: model.menuBarTitle
            )
        }
        .menuBarExtraStyle(.window)
    }
}
