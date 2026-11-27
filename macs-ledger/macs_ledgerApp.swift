import SwiftUI

@main
struct macs_ledgerApp: App {
    @State private var store = LedgerStore.shared

    init() {
        LedgerStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
