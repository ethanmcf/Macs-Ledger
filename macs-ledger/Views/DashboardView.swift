import SwiftUI

/// Main page: this month's total, its spending per category, and this year so far. Past months and years are on History.
struct DashboardView: View {
    @Environment(LedgerStore.self) private var store

    /// Newest first.
    private var expenses: [Expense] { store.expenses }

    @State private var showsAllCategories = false

    private let currencyCode = "CAD"
    private let month = Month.current
    /// Categories shown in the breakdown before it is expanded.
    private let categoryLimit = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                monthTotalHeader
                categoryBreakdown
                yearStats
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 96)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Derived data
    private var thisMonthExpenses: [Expense] {
        expenses.filter { $0.monthKey == month.key }
    }

    private var monthTotal: Decimal { thisMonthExpenses.reduce(0) { $0 + $1.amount } }

    /// This month's spending per category, largest first. Only categories with spending.
    private var categoryTotals: [CategoryTotal] { CategoryTotal.totals(for: thisMonthExpenses, in: store) }

    /// This year's spending per month, up to and including this month. Only months with spending.
    private var thisYearMonthTotals: [Decimal] {
        Dictionary(grouping: expenses.filter { $0.monthKey / 100 == month.year && $0.monthKey <= month.key }, by: \.monthKey)
            .values
            .map { $0.reduce(0) { $0 + $1.amount } }
    }

    private var yearToDate: Decimal { thisYearMonthTotals.reduce(0, +) }

    /// Average spend across this year's months that have spending (including the current month).
    private var monthlyAverage: Decimal {
        let months = thisYearMonthTotals
        return months.isEmpty ? 0 : yearToDate / Decimal(months.count)
    }

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
        }
        .padding(.top, 8)
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
                }
            }
        }
    }

    private var yearStats: some View {
        Card(title: "This year") {
            HStack(spacing: 16) {
                yearSummaryStat("Total spent", yearToDate)
                Divider()
                yearSummaryStat("Monthly average", monthlyAverage)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func yearSummaryStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
