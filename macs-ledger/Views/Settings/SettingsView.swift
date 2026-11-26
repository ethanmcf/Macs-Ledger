import SwiftUI
import SwiftData

/// Opened from the gear button: manage categories and import old data.
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
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
