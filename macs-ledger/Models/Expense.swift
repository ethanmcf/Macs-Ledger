import Foundation
import FirebaseFirestore

/// One expense. Stored at `ledgers/{key}/expenses/{id}`, where `id` is Firestore's auto ID.
struct Expense: Identifiable, Hashable {
    let id: String
    var amount: Decimal
    var date: Date
    var monthKey: Int
    var note: String
    /// The category's document ID. Nil means uncategorized.
    var categoryId: String?

    static let importedNote = "Imported"

    var isImported: Bool { note == Self.importedNote }

    init(id: String, amount: Decimal, categoryId: String?, date: Date = .now, note: String = "") {
        self.id = id
        self.amount = amount
        self.categoryId = categoryId
        self.date = date
        self.monthKey = Month(containing: date).key
        self.note = note
    }

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        let date = (data["date"] as? Timestamp)?.dateValue() ?? .distantPast
        self.id = document.documentID
        self.amount = Self.decimal(fromStored: data["amount"])
        self.date = date
        self.monthKey = data["monthKey"] as? Int ?? Month(containing: date).key
        self.note = data["note"] as? String ?? ""
        self.categoryId = data["categoryId"] as? String
    }

    var fields: [String: Any] {
        var fields: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "date": Timestamp(date: date),
            "monthKey": monthKey,
            "note": note,
        ]
        fields["categoryId"] = categoryId ?? NSNull()
        return fields
    }

    /// A stored number back to an exact amount in cents (42.18 stays 42.18, not 42.179999…).
    private static func decimal(fromStored value: Any?) -> Decimal {
        let number = (value as? NSNumber)?.doubleValue ?? 0
        let cents = (number * 100).rounded()
        return Decimal(Int64(cents)) / 100
    }
}
