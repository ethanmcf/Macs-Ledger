import SwiftUI
import SwiftData

@main
struct macs_ledgerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Category.self, Expense.self, PendingChange.self)
        } catch {
            fatalError("Couldn't open the ledger database: \(error)")
        }
        SyncService.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Send anything still queued whenever the app comes to the foreground.
            if phase == .active { SyncService.shared.scheduleSync(after: .zero) }
        }
    }
}
