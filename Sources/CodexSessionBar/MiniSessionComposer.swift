import SwiftUI

struct MiniSessionComposer: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var draftText: String
    @Binding var selectedModel: String?
    @Binding var selectedReasoningEffort: ReasoningEffortValue?
    @Binding var fastModeEnabled: Bool

    let availableModels: [CodexModel]
    let selectedModelDetails: CodexModel?
    let availableReasoningEfforts: [ReasoningEffortValue]
    let isLoadingModels: Bool
    let isSending: Bool
    let composerFocusNamespace: Namespace.ID
    let composerFocused: FocusState<Bool>.Binding
    let sendMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                controlsRow
            }
            .padding(.leading, LayoutMetrics.inlineLeadingInset)
            .padding(.trailing, LayoutMetrics.inlineTrailingInset)

            inputField
        }
        .padding(.horizontal, LayoutMetrics.panelHorizontalInset)
        .padding(.vertical, LayoutMetrics.composerVerticalInset)
        .background(AdaptivePalette.composerBarBackground(for: colorScheme))
    }

    private var controlsRow: some View {
        Group {
            MiniSelectorMenu(title: "Model", value: modelLabel, isLoading: isLoadingModels) {
                ForEach(availableModels) { model in
                    selectorOption(model.displayName, isSelected: selectedModel == model.model) {
                        selectedModel = model.model
                    }
                }
            }
            .layoutPriority(1)

            MiniSelectorMenu(title: "Reasoning", value: reasoningLabel) {
                ForEach(availableReasoningEfforts, id: \.self) { effort in
                    selectorOption(effort.label, isSelected: selectedReasoningEffort == effort) {
                        selectedReasoningEffort = effort
                    }
                }
            }
            .layoutPriority(1)

            HStack(spacing: 10) {
                Text("Fast")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle("", isOn: $fastModeEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.leading, LayoutMetrics.inlineLeadingInset)
            .padding(.trailing, LayoutMetrics.inlineTrailingInset)
            .padding(.vertical, LayoutMetrics.compactControlVerticalInset)
            .overlay {
                Capsule()
                    .strokeBorder(AdaptivePalette.controlStroke(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: AdaptivePalette.controlShadow(for: colorScheme), radius: 12, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fast")
        }
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            ComposerTextField(
                text: $draftText,
                isSending: isSending,
                focusNamespace: composerFocusNamespace,
                isFocused: composerFocused,
                onSubmit: sendMessage
            )

            Button(action: sendMessage) {
                Image(systemName: isSending ? "waveform" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AdaptivePalette.sendButtonForeground(disabled: isSendDisabled))
            .background(
                Circle()
                    .fill(AdaptivePalette.sendButtonFill(for: colorScheme, disabled: isSendDisabled))
            )
            .disabled(isSendDisabled)
        }
        .padding(.leading, LayoutMetrics.inlineLeadingInset)
        .padding(.trailing, LayoutMetrics.inlineTrailingInset)
        .padding(.vertical, 8)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdaptivePalette.chromeStroke(for: colorScheme), lineWidth: 1)
        }
    }

    private var isSendDisabled: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
    }

    private var modelLabel: String {
        if isLoadingModels && availableModels.isEmpty {
            return "Loading…"
        }

        if let selectedModel,
           let option = availableModels.first(where: { $0.model == selectedModel }) {
            return option.displayName
        }

        if let selectedModelDetails {
            return selectedModelDetails.displayName
        }

        return "Unavailable"
    }

    private var reasoningLabel: String {
        if let selectedReasoningEffort {
            return selectedReasoningEffort.label
        }

        if let selectedModelDetails {
            return selectedModelDetails.defaultReasoningEffort.label
        }

        return "Unavailable"
    }

    private func selectorOption(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
