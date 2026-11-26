import Foundation
import SwiftData

/// Add / delete helpers for categories and expenses.
///
/// Every change also records a `PendingChange` in the same save, so it can be backed up to the
/// Google Sheet later (see `SyncService`). Nothing here touches the network.
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
        try recordChange(.upsert, category, in: context)
        try saveAndSync(context)
        return category
    }

    /// Renames a category and/or changes its icon.
    static func updateCategory(_ category: Category, name: String, icon: String, in context: ModelContext) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyName }
        let others = try context.fetch(FetchDescriptor<Category>()).filter { $0 != category }
        guard !others.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LedgerError.duplicateCategory(trimmed)
        }
        let renamed = category.name != trimmed
        category.name = trimmed
        category.icon = icon
        try recordChange(.upsert, category, in: context)
        // The sheet shows each expense's category name, so re-send them after a rename.
        if renamed {
            for expense in category.expenses { try recordChange(.upsert, expense, in: context) }
        }
        try saveAndSync(context)
    }

    /// Hides or shows a category in quick entry. Its expenses are unaffected.
    static func setHidden(_ hidden: Bool, for category: Category, in context: ModelContext) throws {
        category.isHidden = hidden
        try recordChange(.upsert, category, in: context)
        try saveAndSync(context)
    }

    /// Saves a new chip order: each category's position in the array becomes its sortOrder.
    static func reorder(_ categories: [Category], in context: ModelContext) throws {
        for (index, category) in categories.enumerated() where category.sortOrder != index {
            category.sortOrder = index
            try recordChange(.upsert, category, in: context)
        }
        try saveAndSync(context)
    }

    /// Moves every expense to another category, then deletes the now-empty category.
    static func deleteCategory(_ category: Category, movingExpensesTo destination: Category, in context: ModelContext) throws {
        for expense in Array(category.expenses) {
            expense.category = destination
            try recordChange(.upsert, expense, in: context)
        }
        try recordChange(.delete, category, in: context)
        context.delete(category)
        try saveAndSync(context)
    }

    /// Deletes the category and all of its expenses.
    static func deleteCategoryAndExpenses(_ category: Category, in context: ModelContext) throws {
        for expense in Array(category.expenses) {
            try recordChange(.delete, expense, in: context)
            context.delete(expense)
        }
        try recordChange(.delete, category, in: context)
        context.delete(category)
        try saveAndSync(context)
    }

    /// Inserts the default categories if none exist yet.
    /// Not recorded for backup on purpose: after a reinstall, "Update from Google Sheet" matches these by name
    /// to the sheet's categories. A default is backed up the first time it's used (see `recordChange`).
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
        try recordChange(.upsert, expense, in: context)
        try saveAndSync(context)
        return expense
    }

    /// Saves edits to an expense. Recomputes its month so it moves if the date changed.
    static func updateExpense(_ expense: Expense, amount: Decimal, category: Category, date: Date, in context: ModelContext) throws {
        guard amount > 0 else { throw LedgerError.invalidAmount }
        expense.amount = amount
        expense.category = category
        expense.date = date
        expense.monthKey = Month(containing: date).key
        try recordChange(.upsert, expense, in: context)
        try saveAndSync(context)
    }

    static func deleteExpense(_ expense: Expense, in context: ModelContext) throws {
        try recordChange(.delete, expense, in: context)
        context.delete(expense)
        try saveAndSync(context)
    }

    // MARK: Backup recording

    /// Queues a change for the Google Sheet. Call it before `save()` (and before `delete` for deletions),
    /// so the change and its queue entry are saved together. A newer change replaces an older queued one
    /// for the same record, so only the latest version is sent.
    static func recordChange(_ op: SyncChange.Op, _ expense: Expense, in context: ModelContext) throws {
        let id = ensureUUID(expense)
        let now = Date.now
        expense.updatedAt = now
        // An expense's category must exist in the sheet too. Categories never backed up (e.g. the
        // starter defaults) have no updatedAt yet.
        if op == .upsert, let category = expense.category, category.updatedAt == nil {
            try recordChange(.upsert, category, in: context)
        }
        var change = SyncChange(kind: .expense, op: op, id: id.uuidString, updatedAt: SyncFormat.timestamp(now))
        if op == .upsert {
            change.date = SyncFormat.day.string(from: expense.date)
            change.category = expense.category?.name
            change.categoryId = expense.category.map { ensureUUID($0).uuidString }
            change.amount = SyncFormat.amount(expense.amount)
            change.note = expense.note
        }
        try enqueue(change, recordID: id, in: context)
    }

    static func recordChange(_ op: SyncChange.Op, _ category: Category, in context: ModelContext) throws {
        let id = ensureUUID(category)
        let now = Date.now
        category.updatedAt = now
        var change = SyncChange(kind: .category, op: op, id: id.uuidString, updatedAt: SyncFormat.timestamp(now))
        if op == .upsert {
            change.name = category.name
            change.icon = category.icon
            change.sortOrder = category.sortOrder
            change.hidden = category.isHidden
        }
        try enqueue(change, recordID: id, in: context)
    }

    private static func enqueue(_ change: SyncChange, recordID: UUID, in context: ModelContext) throws {
        let kind = change.kind.rawValue
        let older = try context.fetch(FetchDescriptor<PendingChange>(
            predicate: #Predicate { $0.recordID == recordID && $0.kind == kind }
        ))
        older.forEach(context.delete)
        context.insert(try PendingChange(change: change, recordID: recordID))
    }

    @discardableResult
    static func ensureUUID(_ expense: Expense) -> UUID {
        if let id = expense.uuid { return id }
        let id = UUID()
        expense.uuid = id
        return id
    }

    @discardableResult
    static func ensureUUID(_ category: Category) -> UUID {
        if let id = category.uuid { return id }
        let id = UUID()
        category.uuid = id
        return id
    }

    /// Run once at launch: gives every record a unique ID. Rows saved before backup existed have none, and a
    /// migration could in theory give several rows the same one, so duplicates are re-assigned too.
    static func prepareForSync(in context: ModelContext) throws {
        var seen = Set<UUID>()
        var changed = false
        for expense in try context.fetch(FetchDescriptor<Expense>()) {
            if let id = expense.uuid, seen.insert(id).inserted { continue }
            let id = UUID()
            expense.uuid = id
            seen.insert(id)
            changed = true
        }
        seen.removeAll()
        for category in try context.fetch(FetchDescriptor<Category>()) {
            if let id = category.uuid, seen.insert(id).inserted { continue }
            let id = UUID()
            category.uuid = id
            seen.insert(id)
            changed = true
        }
        if changed { try context.save() }
    }

    /// Saves, then asks the sync service to send queued changes soon. Saving never waits on the network.
    static func saveAndSync(_ context: ModelContext) throws {
        try context.save()
        SyncService.shared.scheduleSync()
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
