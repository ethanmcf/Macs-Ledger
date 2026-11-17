import Foundation

/// A calendar month, used to group expenses and spending totals.
struct Month: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int // 1...12

    /// Compact sortable key stored on `Expense`, e.g. 202611.
    var key: Int { year * 100 + month }
    var id: Int { key }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(key: Int) {
        self.init(year: key / 100, month: key % 100)
    }

    init(containing date: Date = .now, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    static var current: Month { Month() }

    var startDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    var previous: Month { month == 1 ? Month(year: year - 1, month: 12) : Month(year: year, month: month - 1) }
    var next: Month { month == 12 ? Month(year: year + 1, month: 1) : Month(year: year, month: month + 1) }

    /// e.g. "November 2026"
    var title: String { startDate.formatted(.dateTime.month(.wide).year()) }

    static func < (lhs: Month, rhs: Month) -> Bool { lhs.key < rhs.key }
}
