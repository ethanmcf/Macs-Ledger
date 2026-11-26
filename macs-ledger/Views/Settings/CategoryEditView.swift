import SwiftUI
import SwiftData

/// Create a category (`category == nil`) or edit, hide and delete an existing one.
struct CategoryEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]

    let category: Category?

    @State private var name: String
    @State private var icon: String
    @State private var isHidden: Bool
    @State private var confirmingDelete = false
    @State private var choosingMoveTarget = false
    @State private var errorMessage: String?

    private let accent = Color.appAccent
    private let currencyCode = "CAD"

    init(category: Category?) {
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "tag.fill")
        _isHidden = State(initialValue: category?.isHidden ?? false)
    }

    private var isNew: Bool { category == nil }
    /// The category, unless it has just been deleted (this screen is still closing).
    private var liveCategory: Category? {
        guard let category, category.modelContext != nil, !category.isDeleted else { return nil }
        return category
    }
    private var expenseCount: Int { liveCategory?.expenses.count ?? 0 }
    private var expenseTotal: Decimal { liveCategory?.expenses.reduce(0) { $0 + $1.amount } ?? 0 }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Category name", text: $name)
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Category.iconChoices, id: \.self) { symbol in
                        let isSelected = symbol == icon
                        Button { icon = symbol } label: {
                            Image(systemName: symbol)
                                .font(.body)
                                .frame(width: 40, height: 40)
                                .foregroundStyle(isSelected ? Color.onAccent : .primary)
                                .background(Circle().fill(isSelected ? accent : Color(UIColor.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            if let category = liveCategory {
                Section {
                    Toggle("Hide from quick entry", isOn: $isHidden)
                        .onChange(of: isHidden) { _, hidden in
                            try? LedgerStore.setHidden(hidden, for: category, in: context)
                        }
                } footer: {
                    Text("Hidden categories still count in your totals and history.")
                }

                Section {
                    Button("Delete Category", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    if expenseCount > 0 {
                        Text("\(category.name) has \(expenseCount) \(expenseCount == 1 ? "expense" : "expenses") totalling \(expenseTotal.formatted(.currency(code: currencyCode))).")
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Category" : "Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            if let category = liveCategory {
                if expenseCount == 0 {
                    Button("Delete", role: .destructive) {
                        run { try LedgerStore.deleteCategoryAndExpenses(category, in: context) }
                    }
                } else {
                    if allCategories.count > 1 {
                        Button("Move Expenses to Another Category…") { choosingMoveTarget = true }
                    }
                    Button("Delete Category and Its Expenses", role: .destructive) {
                        run { try LedgerStore.deleteCategoryAndExpenses(category, in: context) }
                    }
                }
            }
        } message: {
            if expenseCount > 0 {
                Text("Moving keeps your past totals the same. Deleting the expenses removes them from every month and year total. To keep everything but stop seeing it in quick entry, use Hide instead.")
            }
        }
        .sheet(isPresented: $choosingMoveTarget) {
            if let category = liveCategory {
                MoveExpensesView(source: category, candidates: allCategories.filter { $0 != category }) { destination in
                    choosingMoveTarget = false
                    run { try LedgerStore.deleteCategory(category, movingExpensesTo: destination, in: context) }
                }
            }
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var deleteTitle: String {
        guard let category = liveCategory else { return "" }
        return expenseCount == 0
            ? "Delete \(category.name)?"
            : "\(category.name) has \(expenseCount) \(expenseCount == 1 ? "expense" : "expenses"). What should happen to \(expenseCount == 1 ? "it" : "them")?"
    }

    private func save() {
        run {
            if let category {
                try LedgerStore.updateCategory(category, name: trimmedName, icon: icon, in: context)
            } else {
                try LedgerStore.addCategory(name: trimmedName, icon: icon, in: context)
            }
        }
    }

    /// Runs a store action, then closes this screen, or shows the error.
    private func run(_ action: () throws -> Void) {
        do {
            try action()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Picks which category receives a deleted category's expenses.
private struct MoveExpensesView: View {
    @Environment(\.dismiss) private var dismiss

    let source: Category
    let candidates: [Category]
    let onChoose: (Category) -> Void

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    onChoose(candidate)
                } label: {
                    Label(candidate.name, systemImage: candidate.icon)
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Move \(source.name) Expenses To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { CategoryEditView(category: nil) }
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
