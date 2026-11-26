import SwiftUI
import SwiftData

/// List of categories: tap to edit, drag to reorder, + to add.
struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var isAdding = false

    private let accent = Color.appAccent

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    NavigationLink {
                        CategoryEditView(category: category)
                    } label: {
                        row(category)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Drag to change the order of the chips in quick entry. Hidden categories keep their history but don't appear in quick entry.")
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Category", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { CategoryEditView(category: nil) }
        }
    }

    private func row(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.footnote)
                .foregroundStyle(category.isHidden ? Color.secondary : accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill((category.isHidden ? Color.secondary : accent).opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(category.isHidden ? .secondary : .primary)
                Text("\(category.expenses.count) \(category.expenses.count == 1 ? "expense" : "expenses")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if category.isHidden {
                Label("Hidden", systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = categories
        reordered.move(fromOffsets: source, toOffset: destination)
        try? LedgerStore.reorder(reordered, in: context)
    }
}

#Preview {
    NavigationStack { CategoriesView() }
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
