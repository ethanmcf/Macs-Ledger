import SwiftUI

/// Main page: this month's spending, top categories, year-to-date stats and month history.
struct DashboardView: View {
    @Environment(LedgerStore.self) private var store

    /// Newest first.
    private var expenses: [Expense] { store.expenses }

    @State private var showsAllPreviousMonths = false
    @State private var showsAllCategories = false

    private let accent = Color.appAccent
    private let currencyCode = "CAD"
    private let month = Month.current
    /// Previous months shown before the list is expanded.
    private let previousMonthsLimit = 12
    /// Categories shown in the breakdown before it is expanded.
    private let categoryLimit = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                monthTotalHeader
                categoryBreakdown
                yearStats
                previousMonths
                previousYears
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 96)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Derived data
    private func total(_ items: some Sequence<Expense>) -> Decimal {
        items.reduce(0) { $0 + $1.amount }
    }

    private var thisMonthExpenses: [Expense] {
        expenses.filter { $0.monthKey == month.key }
    }

    private var monthTotal: Decimal { total(thisMonthExpenses) }

    /// This month's spending per category, largest first. Only categories with spending.
    private var categoryTotals: [CategoryTotal] { CategoryTotal.totals(for: thisMonthExpenses, in: store) }

    /// Spending per month, newest first, for months that have spending.
    private var monthTotals: [(month: Month, amount: Decimal)] {
        Dictionary(grouping: expenses, by: \.monthKey)
            .filter { $0.key > 0 }
            .map { (Month(key: $0.key), total($0.value)) }
            .sorted { $0.month > $1.month }
    }

    private var yearToDate: Decimal {
        total(expenses.filter { $0.monthKey / 100 == month.year && $0.monthKey <= month.key })
    }

    /// Average spend across this year's months that have spending (including the current month).
    private var monthlyAverage: Decimal {
        let months = monthTotals.filter { $0.month.year == month.year && $0.month <= month }
        guard !months.isEmpty else { return 0 }
        return total(months.map(\.amount)) / Decimal(months.count)
    }

    private var previousMonthTotals: [(month: Month, amount: Decimal)] {
        monthTotals.filter { $0.month < month }
    }

    /// Earlier years with spending, newest first
    private var previousYearTotals: [YearTotal] {
        Dictionary(grouping: monthTotals.filter { $0.month.year < month.year }, by: \.month.year)
            .map { year, months in
                let spent = total(months.map(\.amount))
                return YearTotal(year: year, total: spent, monthlyAverage: spent / Decimal(months.count))
            }
            .sorted { $0.year > $1.year }
    }

    private func total(_ amounts: [Decimal]) -> Decimal { amounts.reduce(0, +) }

    private func share(_ amount: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return (amount / whole).doubleValue
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
                emptyState("Add an expense to see your breakdown")
            } else {
                let hiddenCount = categoryTotals.count - categoryLimit
                let items = showsAllCategories ? categoryTotals : Array(categoryTotals.prefix(categoryLimit))
                VStack(spacing: 14) {
                    CategoryBreakdownRows(items: items, total: monthTotal, currencyCode: currencyCode)
                    if hiddenCount > 0 {
                        expandButton(isExpanded: $showsAllCategories, hiddenCount: hiddenCount)
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

    private var previousMonths: some View {
        Card(title: "Previous months") {
            let allRows = previousMonthTotals
            if allRows.isEmpty {
                emptyState("Past months will appear here")
            } else {
                // Scale bars against every month so they don't jump when expanding.
                let largest = allRows.map(\.amount).max() ?? 0
                let hiddenCount = allRows.count - previousMonthsLimit
                let rows = showsAllPreviousMonths ? allRows : Array(allRows.prefix(previousMonthsLimit))
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.month) { index, row in
                        if index > 0 { Divider() }
                        NavigationLink {
                            MonthDetailView(month: row.month)
                        } label: {
                            HStack(spacing: 12) {
                                Text(row.month.title)
                                    .font(.subheadline)
                                    .frame(width: 130, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(accent.opacity(0.25))
                                        .frame(width: max(4, geo.size.width * share(row.amount, of: largest)))
                                        .frame(maxHeight: .infinity)
                                }
                                .frame(height: 6)
                                Text(row.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if hiddenCount > 0 {
                        Divider()
                        expandButton(isExpanded: $showsAllPreviousMonths, hiddenCount: hiddenCount)
                            .padding(.top, 12)
                    }
                }
            }
        }
    }

    /// One card per earlier year, or a placeholder card when there are none.
    @ViewBuilder
    private var previousYears: some View {
        let rows = previousYearTotals
        if rows.isEmpty {
            Card(title: "Previous years") {
                emptyState("Past years will appear here")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Previous years")
                    .font(.headline)
                    .padding(.leading, 4)
                ForEach(rows, id: \.year) { row in
                    Card(title: String(row.year)) {
                        HStack(spacing: 16) {
                            yearSummaryStat("Total spent", row.total, font: .title3.weight(.bold))
                            Divider()
                            yearSummaryStat("Monthly average", row.monthlyAverage, font: .title3.weight(.bold))
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Labeled value used in the current year and Previous years cards.
    private func yearSummaryStat(_ label: String, _ value: Decimal, font: Font = .title2.weight(.bold)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Show N more" / "Show less" toggle for a truncated list.
    private func expandButton(isExpanded: Binding<Bool>, hiddenCount: Int) -> some View {
        Button {
            withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded.wrappedValue ? "Show less" : "Show \(hiddenCount) more")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Supporting types

private struct YearTotal {
    let year: Int
    let total: Decimal
    let monthlyAverage: Decimal
}
