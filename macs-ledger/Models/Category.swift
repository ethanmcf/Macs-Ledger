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

    /// Deleting a category deletes its expenses too.
    @Relationship(deleteRule: .cascade, inverse: \Expense.category)
    var expenses: [Expense] = []

    init(name: String, icon: String = "tag.fill", sortOrder: Int = 0, createdAt: Date = .now) {
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

extension Category {
    /// Sum of this category's expenses for the given month.
    func total(for month: Month) -> Decimal {
        expenses
            .filter { $0.monthKey == month.key }
            .reduce(0) { $0 + $1.amount }
    }

    /// Categories inserted on first launch.
    static let defaults: [(name: String, icon: String)] = [
        ("Food", "fork.knife"),
        ("Transport", "car.fill"),
        ("Subscriptions", "repeat"),
        ("Software", "laptopcomputer"),
        ("Coffee", "cup.and.saucer.fill"),
    ]
}
