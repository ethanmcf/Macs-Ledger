import SwiftUI

/// One expense: category icon and name, date, and amount. Used in Transactions and the dashboard's Current month transactions card.
struct TransactionRow: View {
    @Environment(LedgerStore.self) private var store
    let expense: Expense

    private let accent = Color.appAccent
    private let currencyCode = "CAD"

    var body: some View {
        let category = store.category(id: expense.categoryId)
        HStack(spacing: 12) {
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
