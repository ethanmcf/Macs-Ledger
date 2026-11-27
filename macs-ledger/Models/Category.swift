import Foundation
import FirebaseFirestore

/// A spending category. Stored at `ledgers/{key}/categories/{id}`, where `id` is Firestore's auto ID.
struct Category: Identifiable, Hashable {
    let id: String
    var name: String
    /// SF Symbol name shown on the category chip.
    var icon: String
    /// Position in the chip list (lower comes first).
    var sortOrder: Int
    var createdAt: Date
    /// Hidden categories don't appear in quick entry but keep their history.
    var isHidden: Bool

    init(id: String, name: String, icon: String = "tag.fill", sortOrder: Int = 0, createdAt: Date = .now, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.isHidden = isHidden
    }

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        self.init(
            id: document.documentID,
            name: data["name"] as? String ?? "",
            icon: data["icon"] as? String ?? "tag.fill",
            sortOrder: data["sortOrder"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            isHidden: data["hidden"] as? Bool ?? false
        )
    }

    /// The document's fields, as written to Firestore.
    var fields: [String: Any] {
        ["name": name, "icon": icon, "sortOrder": sortOrder, "createdAt": Timestamp(date: createdAt), "hidden": isHidden]
    }
}

extension Category {
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

    /// Categories added to a brand-new ledger.
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
