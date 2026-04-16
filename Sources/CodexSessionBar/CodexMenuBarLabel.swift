import AppKit
import SwiftUI

struct CodexMenuBarLabel: View {
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "terminal")
            }
        }
    }
}

private extension CodexMenuBarLabel {
    static let menuBarIcon: NSImage? = {
        guard let url = Bundle.module.url(
            forResource: "MenuBarIcon",
            withExtension: "svg"
        ),
        let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
