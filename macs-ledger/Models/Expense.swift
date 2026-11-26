import Foundation
import SwiftData

@Model
final class Expense {
    var amount: Decimal
    var date: Date
    var monthKey: Int = 0
    var note: String
    var category: Category?
    /// Stable ID used to match this expense to its row in the Google Sheet backup.
    /// Optional so existing data migrates cleanly; `LedgerStore.prepareForSync` fills in missing ones.
    var uuid: UUID?
    /// Last local change, used to decide whether the app or the sheet has the newer version.
    /// Nil until the expense has been recorded for backup.
    var updatedAt: Date?

    static let importedNote = "Imported"

    var isImported: Bool { note == Self.importedNote }

    init(amount: Decimal, category: Category?, date: Date = .now, note: String = "") {
        self.amount = amount
        self.category = category
        self.date = date
        self.monthKey = Month(containing: date).key
        self.note = note
        self.uuid = UUID()
    }
}
