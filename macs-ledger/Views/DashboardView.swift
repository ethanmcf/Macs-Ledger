import SwiftUI
import SwiftData
import Charts

/// Main page: this month's spending, top categories, year-to-date stats and month history.
struct DashboardView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var presenter = QuickEntryPresenter.shared

    private let accent = Color.indigo
    private let currencyCode = "CAD"
    private let month = Month.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    monthTotalHeader
                    topCategoriesChart
                    categoryBreakdown
                    yearStats
                    previousMonths
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
            }
            .background(Color(UIColor.systemGroupedBackground))
            // .navigationTitle("Ledger")
            .overlay(alignment: .bottomTrailing) { addButton }
        }
        .fontDesign(.rounded)
        .tint(accent)
        .overlay {
            if presenter.isPresented {
                QuickEntryView(month: month) {
                    withAnimation(.snappy) { presenter.isPresented = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: presenter.isPresented)
        .onAppear { try? LedgerStore.seedDefaultsIfNeeded(in: context) }
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
    private var categoryTotals: [CategoryTotal] {
        var sums: [PersistentIdentifier: Decimal] = [:]
        for expense in thisMonthExpenses {
            guard let category = expense.category else { continue }
            sums[category.persistentModelID, default: 0] += expense.amount
        }
        return categories
            .compactMap { category in
                guard let amount = sums[category.persistentModelID], amount > 0 else { return nil }
                return CategoryTotal(name: category.name, icon: category.icon, amount: amount)
            }
            .sorted { $0.amount > $1.amount }
    }

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

    private func total(_ amounts: [Decimal]) -> Decimal { amounts.reduce(0, +) }

    private func share(_ amount: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return (amount / whole).doubleValue
    }

    // MARK: - Sections

    private var monthTotalHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(month.title) · so far")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(monthTotal, format: .currency(code: currencyCode))
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let last = monthTotals.first(where: { $0.month == month.previous }) {
                Text("\(last.amount, format: .currency(code: currencyCode)) spent in \(month.previous.startDate.formatted(.dateTime.month(.wide)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var topCategoriesChart: some View {
        Card(title: "Top categories") {
            let top = Array(categoryTotals.prefix(3))
            if top.isEmpty {
                emptyState("No spending yet this month")
            } else {
                Chart(top) { item in
                    BarMark(
                        x: .value("Category", item.name),
                        y: .value("Amount", item.amount.doubleValue),
                        width: .ratio(0.55)
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))
                    .foregroundStyle(accent.gradient)
                    .annotation(position: .top, spacing: 6) {
                        Text(item.amount, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.primary)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private var categoryBreakdown: some View {
        Card(title: "This month by category") {
            if categoryTotals.isEmpty {
                emptyState("Add an expense to see your breakdown")
            } else {
                VStack(spacing: 14) {
                    ForEach(categoryTotals) { item in
                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .font(.footnote)
                                    .foregroundStyle(accent)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(accent.opacity(0.12)))
                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(share(item.amount, of: monthTotal), format: .percent.precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.amount, format: .currency(code: currencyCode))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .monospacedDigit()
                            ProgressView(value: share(item.amount, of: monthTotal))
                                .tint(accent)
                                .padding(.leading, 38)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Total")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(monthTotal, format: .currency(code: currencyCode))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var yearStats: some View {
        HStack(spacing: 12) {
            StatTile(title: "Spent in \(String(month.year))", value: yearToDate, currencyCode: currencyCode)
            StatTile(title: "Monthly average", value: monthlyAverage, currencyCode: currencyCode)
        }
    }

    private var previousMonths: some View {
        Card(title: "Previous months") {
            let rows = previousMonthTotals
            if rows.isEmpty {
                emptyState("Past months will appear here")
            } else {
                let largest = rows.map(\.amount).max() ?? 0
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.month) { index, row in
                        if index > 0 { Divider() }
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
                            Text(row.amount, format: .currency(code: currencyCode))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(.snappy) { presenter.isPresented = true }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(accent))
                .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
        }
        .padding(20)
        .accessibilityLabel("Add expense")
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Supporting types

private struct CategoryTotal: Identifiable {
    let name: String
    let icon: String
    let amount: Decimal
    var id: String { name }
}

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

private struct StatTile: View {
    let title: String
    let value: Decimal
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

private extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
