import SwiftUI

struct MiniSessionBanner: View {
    let banner: SessionBanner

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(iconColor)

            Text(banner.message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: 1)
        }
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
        tint
    }
}
