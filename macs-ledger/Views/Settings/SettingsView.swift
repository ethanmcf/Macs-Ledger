import SwiftUI
import SwiftData

/// Opened from the gear button: manage categories, import old data, and set up the Google Sheet backup.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "square.grid.2x2")
                }
                NavigationLink {
                    ImportView()
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
                NavigationLink {
                    BackupView()
                } label: {
                    Label("Backup to Google Sheet", systemImage: "icloud")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
        .tint(Color.appAccent)
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Category.self, Expense.self, PendingChange.self], inMemory: true)
}
