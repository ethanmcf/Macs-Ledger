import SwiftUI

/// Opened from the gear button: manage categories, import old data, and see cloud sync.
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
                    CloudSyncView()
                } label: {
                    Label("Cloud Sync", systemImage: "icloud")
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
