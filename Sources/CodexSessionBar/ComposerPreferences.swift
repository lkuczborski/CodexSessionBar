import Foundation

@MainActor
enum ComposerPreferences {
    private enum Key {
        static let selectedModel = "composer.selectedModel"
        static let selectedReasoningEffort = "composer.selectedReasoningEffort"
        static let fastModeEnabled = "composer.fastModeEnabled"
    }

    static var selectedModel: String? {
        selectedModel(in: .standard)
    }

    static func setSelectedModel(_ value: String?) {
        setSelectedModel(value, in: .standard)
    }

    static var selectedReasoningEffort: ReasoningEffortValue? {
        selectedReasoningEffort(in: .standard)
    }

    static func setSelectedReasoningEffort(_ value: ReasoningEffortValue?) {
        setSelectedReasoningEffort(value, in: .standard)
    }

    static var fastModeEnabled: Bool {
        fastModeEnabled(in: .standard)
    }

    static func setFastModeEnabled(_ enabled: Bool) {
        setFastModeEnabled(enabled, in: .standard)
    }

    static func selectedModel(in defaults: UserDefaults) -> String? {
        defaults.string(forKey: Key.selectedModel)
    }

    static func setSelectedModel(_ value: String?, in defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: Key.selectedModel)
        } else {
            defaults.removeObject(forKey: Key.selectedModel)
        }
    }

    static func selectedReasoningEffort(in defaults: UserDefaults) -> ReasoningEffortValue? {
        guard let rawValue = defaults.string(forKey: Key.selectedReasoningEffort) else {
            return nil
        }

        return ReasoningEffortValue(rawValue: rawValue)
    }

    static func setSelectedReasoningEffort(_ value: ReasoningEffortValue?, in defaults: UserDefaults) {
        if let value {
            defaults.set(value.rawValue, forKey: Key.selectedReasoningEffort)
        } else {
            defaults.removeObject(forKey: Key.selectedReasoningEffort)
        }
    }

    static func fastModeEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Key.fastModeEnabled)
    }

    static func setFastModeEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: Key.fastModeEnabled)
    }
}
