import SwiftUI

struct MiniToolbarButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MiniToolbarButtonLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

struct MiniToolbarButtonLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(AdaptivePalette.chromeFill(for: colorScheme), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(AdaptivePalette.chromeStroke(for: colorScheme), lineWidth: 1)
            }
    }
}
