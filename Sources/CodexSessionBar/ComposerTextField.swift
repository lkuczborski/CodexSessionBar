import SwiftUI

struct ComposerTextField: View {
    @Binding var text: String
    let isSending: Bool
    let focusNamespace: Namespace.ID
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField("Ask Codex anything…", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .rounded))
            .focused(isFocused)
            .prefersDefaultFocus(true, in: focusNamespace)
            .lineLimit(1 ... 6)
            .submitLabel(.send)
            .autocorrectionDisabled(true)
            .onKeyPress(.return, phases: [.down]) { keyPress in
                if keyPress.modifiers.contains(.shift) {
                    return .ignored
                }

                if keyPress.modifiers.intersection([.command, .control, .option]).isEmpty, !isSending {
                    onSubmit()
                    return .handled
                }

                return .ignored
            }
    }
}
