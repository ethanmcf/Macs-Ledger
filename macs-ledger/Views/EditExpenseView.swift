
import SwiftUI

/// Sheet for changing or deleting one expense.
struct EditExpenseView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let expense: Expense

    @State private var amount: String
    @State private var categoryId: String?
    @State private var date: Date
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(expense: Expense) {
        self.expense = expense
        _amount = State(initialValue: expense.amount.formatted(.number.precision(.fractionLength(2)).grouping(.never)))
        _categoryId = State(initialValue: expense.categoryId)
        _date = State(initialValue: expense.date)
    }

    /// Visible categories, plus this expense's own category even if it's hidden.
    private var pickerCategories: [Category] {
        store.categories.filter { !$0.isHidden || $0.id == expense.categoryId }
    }

    private var category: Category? { store.category(id: categoryId) }

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
                            Picker("Category", selection: $categoryId) {
                                ForEach(pickerCategories) { item in
                                    Label(item.name, systemImage: item.icon).tag(Optional(item.id))
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
                    store.deleteExpense(expense)
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
            try store.updateExpense(expense, amount: value, category: category, date: date)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
