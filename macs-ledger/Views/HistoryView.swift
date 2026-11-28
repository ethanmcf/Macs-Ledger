import SwiftUI

/// Spending history: every past month (tap one for its breakdown), then a card per earlier year.
struct HistoryView: View {
    @Environment(LedgerStore.self) private var store

    @State private var showsAllPreviousMonths = false

    private let accent = Color.appAccent
    private let currencyCode = "CAD"
    private let month = Month.current
    /// Previous months shown before the list is expanded.
    private let previousMonthsLimit = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                previousMonths
                previousYears
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Derived data

    /// Spending per month, newest first, for months that have spending.
    private var monthTotals: [(month: Month, amount: Decimal)] {
        Dictionary(grouping: store.expenses, by: \.monthKey)
            .filter { $0.key > 0 }
            .map { (Month(key: $0.key), $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.month > $1.month }
    }

    private var previousMonthTotals: [(month: Month, amount: Decimal)] {
        monthTotals.filter { $0.month < month }
    }

    /// Earlier years with spending, newest first. The monthly average counts only months that have spending.
    private var previousYearTotals: [YearTotal] {
        Dictionary(grouping: monthTotals.filter { $0.month.year < month.year }, by: \.month.year)
            .map { year, months in
                let spent = months.reduce(Decimal(0)) { $0 + $1.amount }
                return YearTotal(year: year, total: spent, monthlyAverage: spent / Decimal(months.count))
            }
            .sorted { $0.year > $1.year }
    }

    private func share(_ amount: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return (amount / whole).doubleValue
    }

    // MARK: - Sections

    private var previousMonths: some View {
        Card(title: "Previous months") {
            let allRows = previousMonthTotals
            if allRows.isEmpty {
                EmptyCardMessage("Past months will appear here")
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
                        ExpandButton(isExpanded: $showsAllPreviousMonths, hiddenCount: hiddenCount)
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
                EmptyCardMessage("Past years will appear here")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Previous years")
                    .font(.headline)
                    .padding(.leading, 4)
                ForEach(rows, id: \.year) { row in
                    Card(title: String(row.year)) {
                        HStack(spacing: 16) {
                            yearSummaryStat("Total spent", row.total)
                            Divider()
                            yearSummaryStat("Monthly average", row.monthlyAverage)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Labeled value used in the year cards.
    private func yearSummaryStat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Supporting types

private struct YearTotal {
    let year: Int
    let total: Decimal
    let monthlyAverage: Decimal
}
