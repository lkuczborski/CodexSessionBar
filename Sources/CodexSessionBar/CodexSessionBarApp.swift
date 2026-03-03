import SwiftUI

@main
struct CodexSessionBarApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Label(store.menuBarTitle, systemImage: store.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Codex Sessions", id: "tracker") {
            TrackerWindowView(store: store)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 640)
    }
}
