import SwiftUI
import SwiftData

@main
struct macs_ledgerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Category.self, Expense.self])
    }
}
