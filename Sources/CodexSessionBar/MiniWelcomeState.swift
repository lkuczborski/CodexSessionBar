import SwiftUI

struct MiniWelcomeState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a compact Codex thread")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            Text("The window stays close to the work: a minimal transcript, quick selectors, and a single input that expands only when the prompt needs more room.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Return sends. Shift-Return adds a newline.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}
