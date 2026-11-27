import Foundation
import Observation
import FirebaseCore
import FirebaseFirestore

/// The app's data: every category and expense, kept live from Firestore.
///
/// Everything lives under `ledgers/{ledgerKey}`. The key is a long random string made on first launch and kept
/// in the Keychain. There's no sign-in: knowing the key is what gives access (see `firestore.rules`).
///
/// Firestore's offline cache is the on-phone database. Writes apply to the cache immediately, so the
/// views update right away, even offline, and Firestore uploads them when it can, including after the
/// app restarts. Nothing here waits on the network.
@MainActor
@Observable
final class LedgerStore {
    static let shared = LedgerStore()

    /// All categories, in chip order.
    private(set) var categories: [Category] = []
    /// All expenses, newest first.
    private(set) var expenses: [Expense] = []
    private var categoryByID: [String: Category] = [:]

    // MARK: Status shown in Settings › Cloud Sync

    private(set) var ledgerKey = ""
    /// True until Firestore has heard from the server (offline, or still connecting).
    private(set) var isOffline = true
    /// True while changes made on this phone haven't reached the server yet.
    var hasPendingWrites: Bool { categoriesPending || expensesPending }
    
    var lastError: String? { readError ?? otherError }
    private var readError: String?
    private var otherError: String?

    func dismissError() { otherError = nil }

    private var categoriesPending = false
    private var expensesPending = false
    private var categoriesFromCache = true
    private var expensesFromCache = true

    private let db: Firestore
    private var listeners: [ListenerRegistration] = []

    private enum Keys {
        static let ledgerKey = "ledgerKey"
    }

    // MARK: - Lifecycle

    /// Connects to Firebase using GoogleService-Info.plist (crashes at launch if it's missing).
    private init() {
        FirebaseApp.configure()
        db = Firestore.firestore()
        let settings = db.settings
        // The cache is the app's only copy of the data on the phone, so never let Firestore evict any of it.
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited))
        db.settings = settings
    }

    /// Call once at launch. Starts listening. On the very first launch it makes a new ledger key and adds the
    /// default categories to the new ledger.
    func start() {
        if let key = Keychain.string(for: Keys.ledgerKey), LedgerKey.isValid(key) {
            ledgerKey = key
            listen()
        } else {
            let key = LedgerKey.generate()
            Keychain.set(key, for: Keys.ledgerKey)
            if Keychain.string(for: Keys.ledgerKey) != key {
                otherError = "Couldn't save the ledger key to the Keychain. Copy it from Settings › Cloud Sync before closing the app."
            }
            ledgerKey = key
            listen()
            populateNewLedger()
        }
    }

    /// Switches to another ledger, e.g. on a new phone: paste the key from Settings › Cloud Sync on the old one.
    func useLedger(key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LedgerKey.isValid(trimmed) else { throw LedgerError.invalidKey }
        guard trimmed != ledgerKey else { return }
        Keychain.set(trimmed, for: Keys.ledgerKey)
        ledgerKey = trimmed
        categories = []
        expenses = []
        categoryByID = [:]
        readError = nil
        otherError = nil
        listen()
    }

    /// Only used after `start()`, which always sets `ledgerKey`.
    private var ledger: DocumentReference {
        db.collection("ledgers").document(ledgerKey)
    }

    private func listen() {
        listeners.forEach { $0.remove() }
        listeners = []

        // Snapshots arrive on the main queue.
        listeners.append(ledger.collection("categories").addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let snapshot else { return self.reportReadError(error) }
                self.categories = snapshot.documents.map(Category.init(document:))
                    .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                self.categoryByID = Dictionary(self.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.categoriesPending = snapshot.metadata.hasPendingWrites
                self.categoriesFromCache = snapshot.metadata.isFromCache
                self.updateStatus()
            }
        })
        listeners.append(ledger.collection("expenses").addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let snapshot else { return self.reportReadError(error) }
                self.expenses = snapshot.documents.map(Expense.init(document:)).sorted { $0.date > $1.date }
                self.expensesPending = snapshot.metadata.hasPendingWrites
                self.expensesFromCache = snapshot.metadata.isFromCache
                self.updateStatus()
            }
        })
    }

    private func updateStatus() {
        isOffline = categoriesFromCache || expensesFromCache
        readError = nil
    }

    private func reportReadError(_ error: Error?) {
        guard let error else { return }
        readError = Self.describe(error)
    }

    private static func describe(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == FirestoreErrorDomain, error.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Firestore refused access. Check that the rules in firestore.rules are published in the Firebase console."
        }
        return error.localizedDescription
    }

    /// A brand-new ledger is empty, so this needs no network: add the default categories.
    private func populateNewLedger() {
        commit(Category.defaults.enumerated().map { index, item in
            .setCategory(Category(id: newID(), name: item.name, icon: item.icon, sortOrder: index))
        })
    }

    // MARK: - Writing

    enum Change {
        case setCategory(Category)
        case deleteCategory(String)
        case setExpense(Expense)
        case deleteExpense(String)
    }

    /// A new document ID. Firestore makes these on the phone, so this works offline.
    func newID() -> String {
        ledger.collection("expenses").document().documentID
    }

    /// Applies changes together. Firestore allows 500 writes per batch, so bigger sets are split.
    func commit(_ changes: [Change]) {
        let categoriesRef = ledger.collection("categories")
        let expensesRef = ledger.collection("expenses")
        for start in stride(from: 0, to: changes.count, by: 500) {
            let batch = ledger.firestore.batch()
            for change in changes[start..<min(start + 500, changes.count)] {
                switch change {
                case .setCategory(let category): batch.setData(category.fields, forDocument: categoriesRef.document(category.id))
                case .deleteCategory(let id): batch.deleteDocument(categoriesRef.document(id))
                case .setExpense(let expense): batch.setData(expense.fields, forDocument: expensesRef.document(expense.id))
                case .deleteExpense(let id): batch.deleteDocument(expensesRef.document(id))
                }
            }
            // The completion runs once the server accepts or rejects the batch, which may be much later.
            // Don't wait for it: the change is already in the cache and on screen.
            batch.commit { [weak self] error in
                guard let error else { return }
                let message = "A change couldn't be saved to the cloud: " + Self.describe(error)
                Task { @MainActor in self?.otherError = message }
            }
        }
    }

    // MARK: Categories

    func category(id: String?) -> Category? {
        id.flatMap { categoryByID[$0] }
    }

    func expenses(in category: Category) -> [Expense] {
        expenses.filter { $0.categoryId == category.id }
    }

    /// Categories shown in quick entry.
    var visibleCategories: [Category] {
        categories.filter { !$0.isHidden }
    }

    @discardableResult
    func addCategory(name: String, icon: String = "tag.fill") throws -> Category {
        let trimmed = try validName(name, excluding: nil)
        let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(id: newID(), name: trimmed, icon: icon, sortOrder: nextOrder)
        commit([.setCategory(category)])
        return category
    }

    /// Renames a category and/or changes its icon.
    func updateCategory(_ category: Category, name: String, icon: String) throws {
        var updated = category
        updated.name = try validName(name, excluding: category.id)
        updated.icon = icon
        commit([.setCategory(updated)])
    }

    /// Hides or shows a category in quick entry. Its expenses are unaffected.
    func setHidden(_ hidden: Bool, for category: Category) {
        var updated = category
        updated.isHidden = hidden
        commit([.setCategory(updated)])
    }

    /// Saves a new chip order: each category's position in the array becomes its sortOrder.
    func reorder(_ categories: [Category]) {
        commit(categories.enumerated().compactMap { index, category in
            guard category.sortOrder != index else { return nil }
            var updated = category
            updated.sortOrder = index
            return .setCategory(updated)
        })
    }

    /// Moves every expense to another category, then deletes the now-empty category.
    func deleteCategory(_ category: Category, movingExpensesTo destination: Category) {
        let moves = expenses(in: category).map { expense -> Change in
            var moved = expense
            moved.categoryId = destination.id
            return .setExpense(moved)
        }
        commit(moves + [.deleteCategory(category.id)])
    }

    /// Deletes the category and all of its expenses.
    func deleteCategoryAndExpenses(_ category: Category) {
        commit(expenses(in: category).map { .deleteExpense($0.id) } + [.deleteCategory(category.id)])
    }

    private func validName(_ name: String, excluding id: String?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LedgerError.emptyName }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw LedgerError.duplicateCategory(trimmed)
        }
        return trimmed
    }

    // MARK: Expenses

    func addExpense(amount: Decimal, category: Category, date: Date = .now, note: String = "") throws {
        guard amount > 0 else { throw LedgerError.invalidAmount }
        commit([.setExpense(Expense(id: newID(), amount: amount, categoryId: category.id, date: date, note: note))])
    }

    /// Saves edits to an expense. Recomputes its month so it moves if the date changed.
    func updateExpense(_ expense: Expense, amount: Decimal, category: Category, date: Date) throws {
        guard amount > 0 else { throw LedgerError.invalidAmount }
        var updated = expense
        updated.amount = amount
        updated.categoryId = category.id
        updated.date = date
        updated.monthKey = Month(containing: date).key
        commit([.setExpense(updated)])
    }

    func deleteExpense(_ expense: Expense) {
        commit([.deleteExpense(expense.id)])
    }

    /// Expenses recorded for a month, newest first.
    func expenses(for month: Month) -> [Expense] {
        expenses.filter { $0.monthKey == month.key }
    }
}

// MARK: - Ledger key

enum LedgerKey {
    /// 48 random hex characters. `firestore.rules` only accepts keys that look like this, so short, guessable
    /// paths are refused.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<24).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Same check as `firestore.rules`.
    static func isValid(_ key: String) -> Bool {
        (32...128).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

enum LedgerError: LocalizedError {
    case emptyName
    case duplicateCategory(String)
    case invalidAmount
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .emptyName: "Category name can't be empty."
        case .duplicateCategory(let name): "A category named “\(name)” already exists."
        case .invalidAmount: "Amount must be greater than zero."
        case .invalidKey: "That isn't a ledger key. It should be 32 or more letters and numbers, copied from Settings › Cloud Sync on your other phone."
        }
    }
}
