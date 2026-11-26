import Foundation
import SwiftData

/// A parsed CSV of monthly totals per category, e.g.
///
///     Month,Food,Golf,Car,Total
///     Jan 2024,412.50,80,120,612.50
///
/// The month column is the one titled "Month" (or the first column). A column titled "Total" is
/// only used to double-check each row. Every other column is a category.
struct CSVImport {

    struct Column: Identifiable, Hashable {
        let index: Int
        let header: String
        var id: Int { index }
    }

    enum ParsedMonth: Equatable {
        /// Month and year, e.g. "Jan 2024".
        case full(Month)
        /// A month name with no year, e.g. "January". Needs a year from the user.
        case monthOnly(Int)
        case invalid
    }

    struct Row {
        /// 1-based line number in the file, for warnings.
        let line: Int
        let rawMonth: String
        let month: ParsedMonth
        /// Category column index → amount. Blank and zero cells are left out.
        let amounts: [Int: Decimal]
        let total: Decimal?
        /// Headers of cells that had something in them but weren't a number.
        let unreadableCells: [String]

        func resolvedMonth(fallbackYear: Int) -> Month? {
            switch month {
            case .full(let month): month
            case .monthOnly(let number): Month(year: fallbackYear, month: number)
            case .invalid: nil
            }
        }

        /// True when the file's Total doesn't match the sum of the category cells.
        var totalMismatch: Bool {
            guard let total else { return false }
            let sum = amounts.values.reduce(0, +)
            return abs(NSDecimalNumber(decimal: sum - total).doubleValue) >= 0.01
        }
    }

    let categoryColumns: [Column]
    let rows: [Row]

    var needsYear: Bool { rows.contains { if case .monthOnly = $0.month { true } else { false } } }

    // MARK: - Parsing

    enum ParseError: LocalizedError {
        case empty
        case noCategoryColumns

        var errorDescription: String? {
            switch self {
            case .empty: "The file is empty."
            case .noCategoryColumns: "No category columns were found. The first row should be headers like Month, Food, Car, Total."
            }
        }
    }

    init(text: String) throws {
        let table = Self.splitCSV(text)
        guard let header = table.first else { throw ParseError.empty }

        let headers = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lowered = headers.map { $0.lowercased() }
        let monthIndex = lowered.firstIndex(of: "month") ?? 0
        let totalIndex = lowered.firstIndex(of: "total")

        let columns = headers.enumerated().compactMap { index, title -> Column? in
            guard index != monthIndex, index != totalIndex, !title.isEmpty else { return nil }
            return Column(index: index, header: title)
        }
        guard !columns.isEmpty else { throw ParseError.noCategoryColumns }

        var rows: [Row] = []
        for (offset, cells) in table.dropFirst().enumerated() {
            func cell(_ index: Int) -> String {
                index < cells.count ? cells[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            }
            // Skip fully blank lines.
            guard cells.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }

            var amounts: [Int: Decimal] = [:]
            var unreadable: [String] = []
            for column in columns {
                switch Self.parseAmount(cell(column.index)) {
                case .some(let value?): if value != 0 { amounts[column.index] = value }
                case .some(nil): break // blank
                case nil: unreadable.append(column.header)
                }
            }
            let rawMonth = cell(monthIndex)
            rows.append(Row(
                line: offset + 2,
                rawMonth: rawMonth,
                month: Self.parseMonth(rawMonth),
                amounts: amounts,
                total: totalIndex.flatMap { Self.parseAmount(cell($0)) ?? nil },
                unreadableCells: unreadable
            ))
        }

        self.categoryColumns = columns
        self.rows = rows
    }

    /// Splits CSV text into rows of cells. Handles quoted cells, "" escapes and CRLF line endings.
    static func splitCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cell.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(cell); cell = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(cell); cell = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                cell.append(c)
            }
            i += 1
        }
        return rows
    }

    /// `.some(nil)` for a blank cell, `.some(value)` for a number, `nil` if it isn't a number.
    /// Accepts "$1,240.50", "1240.5", " 80 ". A lone "-" counts as blank.
    static func parseAmount(_ raw: String) -> Decimal?? {
        let cleaned = raw
            .replacingOccurrences(of: "CA$", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty || cleaned == "-" { return .some(nil) }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return .some(value)
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Understands "Jan 2024", "January 2024", "Jan-24", "2024-01", "01/2024", "2024/1",
    /// "2024-01-15", and a bare "January" (month only).
    static func parseMonth(_ raw: String) -> ParsedMonth {
        let tokens = raw.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty else { return .invalid }

        var month: Int?
        var numbers: [String] = []
        for token in tokens {
            if token.first!.isLetter {
                guard month == nil, token.count >= 3,
                      let index = monthNames.firstIndex(of: String(token.prefix(3))) else { return .invalid }
                month = index + 1
            } else {
                numbers.append(token)
            }
        }

        func year(_ token: String) -> Int? {
            guard let value = Int(token) else { return nil }
            switch token.count {
            case 4 where (1900...2100).contains(value): return value
            case 2: return 2000 + value
            default: return nil
            }
        }

        if let month {
            // Month name plus maybe a year.
            switch numbers.count {
            case 0: return .monthOnly(month)
            case 1: return year(numbers[0]).map { .full(Month(year: $0, month: month)) } ?? .invalid
            default: return .invalid
            }
        }

        // All numeric: find the 4-digit year, then the month next to it.
        guard let yearIndex = numbers.firstIndex(where: { $0.count == 4 }),
              let y = year(numbers[yearIndex]) else { return .invalid }
        let rest = numbers.enumerated().filter { $0.offset != yearIndex }.map(\.element)
        let monthToken: String?
        switch (yearIndex, rest.count) {
        case (_, 1): monthToken = rest[0]                       // 2024-01, 01/2024
        case (0, 2): monthToken = rest[0]                       // 2024-01-15
        case (2, 2): monthToken = rest[0]                       // 01/15/2024 (month first)
        default: monthToken = nil
        }
        guard let monthToken, let m = Int(monthToken), (1...12).contains(m) else { return .invalid }
        return .full(Month(year: y, month: m))
    }

    // MARK: - Import

    enum Target: Hashable {
        case skip
        case existing(PersistentIdentifier)
        case create(String)
    }

    /// What one import would add: (month, column) → amount, after skipping unusable rows.
    func plannedAmounts(targets: [Int: Target], fallbackYear: Int) -> [(month: Month, column: Int, amount: Decimal)] {
        rows.flatMap { row -> [(month: Month, column: Int, amount: Decimal)] in
            guard let month = row.resolvedMonth(fallbackYear: fallbackYear) else { return [] }
            return row.amounts.compactMap { column, amount in
                if case .skip = targets[column] ?? .skip { return nil }
                return (month, column, amount)
            }
        }
    }

    /// Creates any new categories, replaces earlier imported totals for the same month and
    /// category, and adds one expense per category per month dated the 1st.
    /// Returns how many expenses were added.
    @discardableResult
    func apply(targets: [Int: Target], fallbackYear: Int, in context: ModelContext) throws -> Int {
        // 1. Resolve each column to a category, creating new ones as needed.
        var categoryForColumn: [Int: Category] = [:]
        var categories = try context.fetch(FetchDescriptor<Category>())
        for column in categoryColumns {
            switch targets[column.index] ?? .skip {
            case .skip:
                continue
            case .existing(let id):
                categoryForColumn[column.index] = categories.first { $0.persistentModelID == id }
            case .create(let rawName):
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    categoryForColumn[column.index] = match
                } else {
                    let created = try LedgerStore.addCategory(name: name, icon: Self.guessIcon(for: name), in: context)
                    categories.append(created)
                    categoryForColumn[column.index] = created
                }
            }
        }

        // 2. Sum per month and category (two columns can point at the same category).
        struct Key: Hashable { let monthKey: Int; let category: PersistentIdentifier }
        var sums: [Key: (month: Month, category: Category, amount: Decimal)] = [:]
        for item in plannedAmounts(targets: targets, fallbackYear: fallbackYear) {
            guard let category = categoryForColumn[item.column] else { continue }
            let key = Key(monthKey: item.month.key, category: category.persistentModelID)
            sums[key, default: (item.month, category, 0)].amount += item.amount
        }

        // 3. Replace earlier imports for the same month + category. Hand-entered expenses are untouched.
        let note = Expense.importedNote
        let previous = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.note == note }))
        for expense in previous {
            guard let category = expense.category else { continue }
            if sums[Key(monthKey: expense.monthKey, category: category.persistentModelID)] != nil {
                try LedgerStore.recordChange(.delete, expense, in: context)
                context.delete(expense)
            }
        }

        // 4. Insert. Each one is also queued for the Google Sheet backup.
        for entry in sums.values where entry.amount > 0 {
            let expense = Expense(amount: entry.amount, category: entry.category, date: entry.month.startDate, note: note)
            context.insert(expense)
            try LedgerStore.recordChange(.upsert, expense, in: context)
        }
        try LedgerStore.saveAndSync(context)
        return sums.count
    }

    /// Picks a sensible icon for common category names; falls back to a tag.
    static func guessIcon(for name: String) -> String {
        let n = name.lowercased()
        let table: [(keys: [String], icon: String)] = [
            (["food", "grocer", "restaurant", "eat"], "fork.knife"),
            (["coffee", "cafe"], "cup.and.saucer.fill"),
            (["golf"], "figure.golf"),
            (["hockey", "hockye"], "figure.hockey"),
            (["car", "gas", "fuel", "transport"], "car.fill"),
            (["cloth", "apparel"], "tshirt.fill"),
            (["cod", "software", "dev", "computer"], "chevron.left.forwardslash.chevron.right"),
            (["subscription"], "repeat"),
            (["gym", "fitness"], "dumbbell.fill"),
            (["travel", "flight"], "airplane"),
            (["rent", "home", "house"], "house.fill"),
            (["gift"], "gift.fill"),
        ]
        return table.first { $0.keys.contains { n.contains($0) } }?.icon ?? "tag.fill"
    }
}
