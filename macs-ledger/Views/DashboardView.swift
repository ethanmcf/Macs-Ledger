import SwiftUI

/// Main page, all about this month: its total against a typical month like it, its spending per category
/// with last month's total, and this month's expenses. Averages and past months are on Trends.
///
/// It compares with last month rather than an average, because spending shifts with the seasons (e.g. summer
/// work vs. the school year). "Average November" compares with the same month in earlier years.
struct DashboardView: View {
    @Environment(LedgerStore.self) private var store

    @State private var showsAllCategories = false
    @State private var showsMoreRecent = false
    @State private var editing: Expense?

    private let currencyCode = "CAD"
    private let month = Month.current
    /// Categories shown in the breakdown before it is expanded.
    private let categoryLimit = 8
    /// This month's expenses shown in the Current month transactions card before it is expanded.
    private let recentLimit = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                monthTotalHeader
                categoryBreakdown
                recent
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 96)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .sheet(item: $editing) { expense in
            EditExpenseView(expense: expense)
        }
    }

    // MARK: - Derived data

    private var thisMonthExpenses: [Expense] { store.expenses(for: month) }

    private var monthTotal: Decimal { thisMonthExpenses.reduce(0) { $0 + $1.amount } }

    /// This month's spending per category, largest first. Only categories with spending.
    private var categoryTotals: [CategoryTotal] { CategoryTotal.totals(for: thisMonthExpenses, in: store) }

    /// Every complete month so far, for "Average November".
    private var averageMonths: [Month] { store.completeMonths() }

    private var lastMonthExpenses: [Expense] { store.expenses(for: month.previous) }

    // MARK: - Sections

    private var monthTotalHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(month.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(monthTotal, format: .currency(code: currencyCode))
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // Same calendar month in earlier years, e.g. "Average November". Shown once there is one.
            if let average = store.monthlyAverage(over: averageMonths.filter { $0.month == month.month }) {
                let difference = monthTotal - average
                HStack(spacing: 4) {
                    Text("Average \(month.startDate.formatted(.dateTime.month(.wide))): \(whole(average))")
                        .foregroundStyle(.secondary)
                    if difference != 0 {
                        Text("·").foregroundStyle(.secondary)
                        differenceText(difference)
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
        .padding(.top, 8)
    }

    /// "$120 over" in orange, or "$480 under so far" in green: this month's total against another amount.
    /// The month isn't over, so being under is "so far"; being over already is final.
    @ViewBuilder
    private func differenceText(_ difference: Decimal) -> some View {
        if difference > 0 {
            Text("\(whole(difference)) over")
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        } else if difference < 0 {
            Text("\(whole(-difference)) under so far")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        }
    }

    /// An amount in whole dollars, e.g. "$1,450".
    private func whole(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    private var categoryBreakdown: some View {
        Card(title: "This month by category") {
            if categoryTotals.isEmpty {
                EmptyCardMessage("Add an expense to see your breakdown")
            } else {
                let hiddenCount = categoryTotals.count - categoryLimit
                let items = showsAllCategories ? categoryTotals : Array(categoryTotals.prefix(categoryLimit))
                VStack(spacing: 14) {
                    CategoryBreakdownRows(items: items, total: monthTotal, currencyCode: currencyCode)
                    if hiddenCount > 0 {
                        ExpandButton(isExpanded: $showsAllCategories, hiddenCount: hiddenCount)
                    }
                    Divider()
                    BreakdownTotalRow(total: monthTotal, currencyCode: currencyCode)
                    if !lastMonthExpenses.isEmpty {
                        let lastTotal = lastMonthExpenses.reduce(Decimal(0)) { $0 + $1.amount }
                        HStack {
                            Text("Last month (\(month.previous.startDate.formatted(.dateTime.month(.wide))))")
                            Spacer()
                            Text(lastTotal, format: .currency(code: currencyCode))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    /// This month's expenses, newest first, so a quick entry can be checked (and fixed) right away.
    @ViewBuilder
    private var recent: some View {
        let all = thisMonthExpenses
        let items = showsMoreRecent ? all : Array(all.prefix(recentLimit))
        let hiddenCount = all.count - recentLimit
        if !items.isEmpty {
            Card(title: "Current month transactions") {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, expense in
                        if index > 0 { Divider() }
                        Button { editing = expense } label: {
                            TransactionRow(expense: expense)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                    if hiddenCount > 0 {
                        Divider()
                        ExpandButton(isExpanded: $showsMoreRecent, hiddenCount: hiddenCount)
                            .padding(.top, 12)
                    }
                }
            }
        }
    }
}
