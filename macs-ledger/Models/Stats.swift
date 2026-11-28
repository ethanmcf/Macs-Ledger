import Foundation

/// Averages and totals shared by the Dashboard and Trends pages.
///
/// Averages only use complete months (this month isn't over yet). They start at the first month with any
/// spending, and months with no spending after that count as $0, so a rare category isn't overstated.
extension LedgerStore {
    /// The first month with any spending.
    var firstMonth: Month? {
        expenses.map(\.monthKey).filter { $0 > 0 }.min().map(Month.init(key:))
    }

    /// Complete months, oldest first: from `start` (or the first month with spending, if later) through last month.
    func completeMonths(from start: Month? = nil) -> [Month] {
        guard var first = firstMonth else { return [] }
        if let start { first = max(first, start) }
        let last = Month.current.previous
        guard first <= last else { return [] }
        return Array(sequence(first: first) { $0 < last ? $0.next : nil })
    }

    /// Total spent across the given months.
    func total(over months: [Month]) -> Decimal {
        let keys = Set(months.map(\.key))
        return expenses.filter { keys.contains($0.monthKey) }.reduce(0) { $0 + $1.amount }
    }

    /// Average spent per month across the given months, or nil if there are none.
    func monthlyAverage(over months: [Month]) -> Decimal? {
        months.isEmpty ? nil : total(over: months) / Decimal(months.count)
    }

    /// Each category's average spending per month across the given months, largest first.
    /// Only categories with spending in those months.
    func categoryAverages(over months: [Month]) -> [CategoryTotal] {
        guard !months.isEmpty else { return [] }
        let keys = Set(months.map(\.key))
        let count = Decimal(months.count)
        return CategoryTotal.totals(for: expenses.filter { keys.contains($0.monthKey) }, in: self)
            .map { CategoryTotal(id: $0.id, name: $0.name, icon: $0.icon, amount: $0.amount / count) }
    }
}
