import SwiftUI
import SwiftData

@main
struct macs_ledgerApp: App {
    var body: some Scene {
        WindowGroup {
            QuickEntryView()
        }
        .modelContainer(for: [Category.self, Expense.self])
    }
}
