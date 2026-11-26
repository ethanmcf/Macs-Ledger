import SwiftUI
import SwiftData

/// One month's total and its spending per category. Opened from Previous months.
struct MonthDetailView: View {
    let month: Month

    @Query private var expenses: [Expense]

    private let currencyCode = "CAD"

    init(month: Month) {
        self.month = month
        let key = month.key
        _expenses = Query(filter: #Predicate<Expense> { $0.monthKey == key })
    }

    private var total: Decimal { expenses.reduce(0) { $0 + $1.amount } }

    var body: some View {
        let items = CategoryTotal.totals(for: expenses)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(total, format: .currency(code: currencyCode))
                    .font(.system(size: 48, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 8)

                Card(title: "By category") {
                    if items.isEmpty {
                        Text("No spending this month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        VStack(spacing: 14) {
                            CategoryBreakdownRows(items: items, total: total, currencyCode: currencyCode)
                            Divider()
                            BreakdownTotalRow(total: total, currencyCode: currencyCode)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(month.title)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }
}

#Preview {
    NavigationStack { MonthDetailView(month: .current) }
        .modelContainer(for: [Category.self, Expense.self, PendingChange.self], inMemory: true)
}
