import AppIntents
import Observation

/// Shared on/off state for the quick entry overlay, so an App Intent can toggle it.
@MainActor
@Observable
final class QuickEntryPresenter {
    static let shared = QuickEntryPresenter()

    var isPresented = false

    func toggle() { isPresented.toggle() }
}

/// Shows or hides the quick entry panel. Bring the app forward when it runs, so it can be
/// bound to Back Tap via a Shortcut (Settings › Accessibility › Touch › Back Tap).
struct ToggleQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Quick Entry"
    static let description = IntentDescription("Shows or hides the quick expense entry panel.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickEntryPresenter.shared.toggle()
        return .result()
    }
}

/// Makes the intent appear in the Shortcuts app automatically, no setup needed.
struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleQuickEntryIntent(),
            phrases: [
                "Toggle quick entry in \(.applicationName)",
                "Add an expense in \(.applicationName)",
            ],
            shortTitle: "Quick Entry",
            systemImageName: "plus.circle.fill"
        )
    }
}
