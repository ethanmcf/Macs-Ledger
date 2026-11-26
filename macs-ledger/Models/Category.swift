import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var name: String
    /// SF Symbol name shown on the category chip.
    var icon: String
    /// Position in the chip list (lower comes first).
    var sortOrder: Int
    var createdAt: Date
    /// Hidden categories don't appear in quick entry but keep their history.
    var isHidden: Bool = false
    /// Stable ID used to match this category to its row in the Google Sheet backup (see `Expense.uuid`).
    var uuid: UUID?
    /// Last local change; nil until the category has been recorded for backup.
    var updatedAt: Date?

    /// Expenses are moved or deleted explicitly before a category is deleted (see `LedgerStore`).
    /// `.nullify` is the safety net: anything left over becomes uncategorized instead of vanishing.
    @Relationship(deleteRule: .nullify, inverse: \Expense.category)
    var expenses: [Expense] = []

    init(name: String, icon: String = "tag.fill", sortOrder: Int = 0, createdAt: Date = .now) {
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.uuid = UUID()
    }
}

extension Category {
    /// Sum of this category's expenses for the given month.
    func total(for month: Month) -> Decimal {
        expenses
            .filter { $0.monthKey == month.key }
            .reduce(0) { $0 + $1.amount }
    }

    /// Icons offered when creating or editing a category.
    static let iconChoices: [String] = [
        "fork.knife", "cart.fill", "cup.and.saucer.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill",
        "car.fill", "fuelpump.fill", "bus.fill", "airplane", "bicycle",
        "house.fill", "bolt.fill", "wifi", "phone.fill", "repeat",
        "laptopcomputer", "chevron.left.forwardslash.chevron.right", "gamecontroller.fill", "tv.fill", "headphones",
        "tshirt.fill", "bag.fill", "gift.fill", "heart.fill", "cross.case.fill",
        "figure.golf", "figure.hockey", "dumbbell.fill", "sportscourt.fill", "pawprint.fill",
        "book.fill", "graduationcap.fill", "wrench.and.screwdriver.fill", "creditcard.fill", "tag.fill",
    ]

    /// Categories inserted on first launch.
    static let defaults: [(name: String, icon: String)] = [
        ("Food", "takeoutbag.and.cup.and.straw.fill"),
        ("Transportation", "car.fill"),
        ("Golf", "figure.golf"),
        ("Hockey", "figure.hockey"),
        ("Clothes", "bag.fill"),
        ("Gifts", "gift.fill"),
        ("Other", "wrench.and.screwdriver.fill"),


    ]
}
