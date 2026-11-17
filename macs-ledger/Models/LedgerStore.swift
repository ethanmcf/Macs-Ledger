import Foundation
import SwiftData

/// Add / delete helpers for categories and expenses.
enum LedgerStore {

    // MARK: Categories

    @discardableResult
    static func addCategory(name: String, icon: String = "tag.fill", in context: ModelContext) throws -> Category {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyName }

        let existing = try context.fetch(FetchDescriptor<Category>())
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LedgerError.duplicateCategory(trimmed)
        }

        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(name: trimmed, icon: icon, sortOrder: nextOrder)
        context.insert(category)
        try context.save()
        return category
    }

    /// Deletes the category and (via cascade) all of its expenses.
    static func deleteCategory(_ category: Category, in context: ModelContext) throws {
        context.delete(category)
        try context.save()
    }

    /// Inserts the default categories if none exist yet.
    static func seedDefaultsIfNeeded(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Category>()) == 0 else { return }
        for (index, item) in Category.defaults.enumerated() {
            context.insert(Category(name: item.name, icon: item.icon, sortOrder: index))
        }
        try context.save()
    }

    // MARK: Expenses

    @discardableResult
    static func addExpense(amount: Decimal, category: Category, date: Date = .now, note: String = "", in context: ModelContext) throws -> Expense {
        guard amount > 0 else { throw LedgerError.invalidAmount }
        let expense = Expense(amount: amount, category: category, date: date, note: note)
        context.insert(expense)
        try context.save()
        return expense
    }

    static func deleteExpense(_ expense: Expense, in context: ModelContext) throws {
        context.delete(expense)
        try context.save()
    }

    // MARK: Monthly totals

    /// All expenses recorded for a month, newest first.
    static func expenses(for month: Month, in context: ModelContext) throws -> [Expense] {
        let key = month.key
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.monthKey == key },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Total spending across all categories for a month.
    static func total(for month: Month, in context: ModelContext) throws -> Decimal {
        try expenses(for: month, in: context).reduce(0) { $0 + $1.amount }
    }

    /// Spending per category for a month. Categories with no spending are included as 0.
    static func categoryTotals(for month: Month, in context: ModelContext) throws -> [Category: Decimal] {
        var totals: [Category: Decimal] = [:]
        for category in try context.fetch(FetchDescriptor<Category>()) {
            totals[category] = 0
        }
        for expense in try expenses(for: month, in: context) {
            guard let category = expense.category else { continue }
            totals[category, default: 0] += expense.amount
        }
        return totals
    }

    /// Months that have at least one expense, newest first.
    static func monthsWithSpending(in context: ModelContext) throws -> [Month] {
        let keys = Set(try context.fetch(FetchDescriptor<Expense>()).map(\.monthKey))
        return keys.filter { $0 > 0 }.map(Month.init(key:)).sorted(by: >)
    }
}

enum LedgerError: LocalizedError {
    case emptyName
    case duplicateCategory(String)
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .emptyName: "Category name can't be empty."
        case .duplicateCategory(let name): "A category named “\(name)” already exists."
        case .invalidAmount: "Amount must be greater than zero."
        }
    }
}
