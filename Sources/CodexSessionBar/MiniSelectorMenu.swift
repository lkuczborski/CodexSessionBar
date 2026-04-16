import SwiftUI

struct MiniSelectorMenu<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    var isLoading: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Menu {
                content
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.primary.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, LayoutMetrics.inlineLeadingInset)
                .padding(.trailing, LayoutMetrics.inlineTrailingInset)
                .frame(height: LayoutMetrics.compactControlHeight)
                .overlay {
                    Capsule()
                        .strokeBorder(AdaptivePalette.controlStroke(for: colorScheme), lineWidth: 1)
                }
                .shadow(color: AdaptivePalette.controlShadow(for: colorScheme), radius: 12, y: 4)
                .opacity(isLoading ? 0.78 : 1)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .layoutPriority(1)
        }
    }
}
