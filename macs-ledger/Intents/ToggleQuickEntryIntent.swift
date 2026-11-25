import AppIntents
import Observation

/// Shared on/off state for the quick entry overlay, so an App Intent can open it.
@MainActor
@Observable
final class QuickEntryPresenter {
    static let shared = QuickEntryPresenter()

    var isPresented = false

    func present() { isPresented = true }
}

struct ToggleQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Opens the quick expense entry panel.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickEntryPresenter.shared.present()
        return .result()
    }
}

/// Makes the intent appear in the Shortcuts app automatically
struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleQuickEntryIntent(),
            phrases: [
                "Open quick entry in \(.applicationName)",
                "Add an expense in \(.applicationName)",
            ],
            shortTitle: "Ledger - Quick Entry",
            systemImageName: "plus.circle.fill"
        )
    }
}
