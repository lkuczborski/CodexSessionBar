import SwiftUI

@main
struct CodexSessionBarApp: App {
    @State private var model = CodexMiniAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuLaunchpadView(model: model)
        } label: {
            Label(model.menuBarTitle, systemImage: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
