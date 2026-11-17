import Foundation
import SwiftData

@Model
final class Expense {
    var amount: Decimal
    var date: Date
    var monthKey: Int = 0
    var note: String
    var category: Category?

    init(amount: Decimal, category: Category?, date: Date = .now, note: String = "") {
        self.amount = amount
        self.category = category
        self.date = date
        self.monthKey = Month(containing: date).key
        self.note = note
    }
}
