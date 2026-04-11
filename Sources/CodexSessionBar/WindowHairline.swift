import SwiftUI

struct WindowHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        AdaptivePalette.hairline(for: colorScheme),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
    }
}
