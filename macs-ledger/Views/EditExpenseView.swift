import SwiftUI
import SwiftData

/// Sheet for changing or deleting one expense.
struct EditExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    let expense: Expense

    @State private var amount: String
    @State private var category: Category?
    @State private var date: Date
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(expense: Expense) {
        self.expense = expense
        _amount = State(initialValue: expense.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never)))
        _category = State(initialValue: expense.category)
        _date = State(initialValue: expense.date)
    }

    /// Visible categories, plus this expense's own category even if it's hidden.
    private var pickerCategories: [Category] {
        categories.filter { !$0.isHidden || $0 == expense.category }
    }

    private var parsedAmount: Decimal? {
        guard let value = Decimal(string: amount, locale: .current), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                    }
                    .font(.title2.weight(.semibold))
                }
                Section {
                    LabeledContent("Category") {
                        Menu {
                            Picker("Category", selection: $category) {
                                ForEach(pickerCategories) { item in
                                    Label(item.name, systemImage: item.icon).tag(Optional(item))
                                }
                            }
                        } label: {
                            // Custom label so the selected category can be smaller and inset from the edge.
                            HStack(spacing: 6) {
                                if let category {
                                    Image(systemName: category.icon)
                                        .font(.caption)
                                    Text(category.name)
                                        .font(.subheadline)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Color.appAccent)
                            .padding(.trailing, 8)
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    Button("Delete Transaction", role: .destructive) { confirmingDelete = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsedAmount == nil || category == nil)
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    try? LedgerStore.deleteExpense(expense, in: context)
                    dismiss()
                }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .fontDesign(.rounded)
    }

    private func save() {
        guard let value = parsedAmount, let category else { return }
        do {
            try LedgerStore.updateExpense(expense, amount: value, category: category, date: date, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Category.self, Expense.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let category = Category(name: "Food", icon: "fork.knife")
    container.mainContext.insert(category)
    let expense = Expense(amount: 24.50, category: category)
    container.mainContext.insert(expense)
    return EditExpenseView(expense: expense)
        .modelContainer(container)
}
