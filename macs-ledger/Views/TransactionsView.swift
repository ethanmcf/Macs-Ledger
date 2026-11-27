import SwiftUI

/// Every expense, grouped by month (newest first). Tap to edit, swipe to delete.
struct TransactionsView: View {
    @Environment(LedgerStore.self) private var store
    private var expenses: [Expense] { store.expenses }

    @State private var showsAllMonths = false
    @State private var editing: Expense?

    private let accent = Color.appAccent
    private let currencyCode = "CAD"
    /// Months shown before the list is expanded.
    private let monthLimit = 3

    /// Expenses grouped by month, newest month first. Expenses within a month stay newest first.
    private var sections: [(month: Month, expenses: [Expense])] {
        Dictionary(grouping: expenses, by: \.monthKey)
            .map { (Month(key: $0.key), $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        let all = sections
        let visible = showsAllMonths ? all : Array(all.prefix(monthLimit))
        let hiddenCount = all.count - monthLimit

        List {
            ForEach(visible, id: \.month) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        Button { editing = expense } label: { row(expense) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteExpense(expense)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(section.month.title)
                        Spacer()
                        Text(section.expenses.reduce(Decimal(0)) { $0 + $1.amount }, format: .currency(code: currencyCode))
                            .monospacedDigit()
                    }
                }
            }

            if hiddenCount > 0 {
                Section {
                    Button {
                        withAnimation(.snappy) { showsAllMonths.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsAllMonths ? "Show less" : "Show \(hiddenCount) older \(hiddenCount == 1 ? "month" : "months")")
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showsAllMonths ? 180 : 0))
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, 96, for: .scrollContent) // room for the add button
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Expenses you add will show up here.")
                )
            }
        }
        .sheet(item: $editing) { expense in
            EditExpenseView(expense: expense)
        }
    }

    private func row(_ expense: Expense) -> some View {
        let category = store.category(id: expense.categoryId)
        return HStack(spacing: 12) {
            Image(systemName: category?.icon ?? "questionmark")
                .font(.footnote)
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(category?.name ?? "Uncategorized")
                    .font(.subheadline.weight(.medium))
                // Imported rows are monthly totals dated the 1st, so a day would be misleading.
                Group {
                    if expense.isImported {
                        Text("Imported monthly total")
                    } else {
                        Text(expense.date, format: .dateTime.month(.abbreviated).day())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.amount, format: .currency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
