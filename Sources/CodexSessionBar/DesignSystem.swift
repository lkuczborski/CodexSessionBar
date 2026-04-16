import SwiftUI

enum LayoutMetrics {
    static let panelHorizontalInset: CGFloat = 18
    static let inlineLeadingInset: CGFloat = 12
    static let inlineTrailingInset: CGFloat = 8
    static let compactControlVerticalInset: CGFloat = 4
    static let compactControlHeight: CGFloat = 28
    static let composerVerticalInset: CGFloat = 10
    static let transcriptVerticalInset: CGFloat = 22
    static let messageOpposingSpacer: CGFloat = 24
    static let messageMaxWidth: CGFloat = 520
}

enum AdaptivePalette {
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.11, blue: 0.13)
            : Color(red: 0.985, green: 0.987, blue: 0.992)
    }

    static func panelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.14)
            : Color(red: 0.992, green: 0.993, blue: 0.996)
    }

    static func composerBarBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.12, green: 0.13, blue: 0.15)
            : Color(red: 0.975, green: 0.978, blue: 0.985)
    }

    static func neutralBadgeTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.09) : .black.opacity(0.06)
    }

    static func chromeFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.045)
    }

    static func chromeStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    static func panelStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.10)
    }

    static func hairline(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.10)
    }

    static func composerFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.18) : .white.opacity(0.78)
    }

    static func sendButtonFill(for colorScheme: ColorScheme, disabled: Bool) -> Color {
        if disabled {
            return colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
        }

        return .accentColor
    }

    static func sendButtonForeground(disabled: Bool) -> Color {
        disabled ? .secondary : .white
    }

    static func controlFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.62)
    }

    static func controlStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.10)
    }

    static func controlShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .clear : .black.opacity(0.06)
    }
}

struct AuroraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AdaptivePalette.windowBackground(for: colorScheme)
            .ignoresSafeArea()
    }
}

struct MiniSessionBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AdaptivePalette.panelBackground(for: colorScheme)
            .ignoresSafeArea()
    }
}

struct LiquidPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AdaptivePalette.chromeFill(for: colorScheme))
                        .glassEffect(.regular.tint(tint.opacity(0.26)), in: .rect(cornerRadius: cornerRadius))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AdaptivePalette.panelStroke(for: colorScheme), lineWidth: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AdaptivePalette.panelStroke(for: colorScheme), lineWidth: 1)
                }
        }
    }
}

extension View {
    func liquidPanel(tint: Color = .cyan, cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidPanelModifier(tint: tint, cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func miniActionButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

struct SessionBadge: View {
    let label: String
    var tint: Color = .white.opacity(0.12)

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
    }
}

struct BannerView: View {
    let banner: SessionBanner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)

            Text(banner.message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .liquidPanel(tint: tint, cornerRadius: 18)
    }

    private var tint: Color {
        switch banner.tone {
        case .info: .cyan
        case .warning: .orange
        case .failure: .red
        }
    }

    private var iconName: String {
        switch banner.tone {
        case .info: "sparkles"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch banner.tone {
        case .info: .cyan
        case .warning: .orange
        case .failure: .red
        }
    }
}
