import Foundation
import SwiftData

/// One change waiting to be sent to the Google Sheet. Saved in the same transaction as the change itself,
/// so nothing is lost if the phone is offline or the app closes. Deleted once the sheet confirms it.
@Model
final class PendingChange {
    /// "expense" or "category".
    var kind: String
    var recordID: UUID
    /// JSON-encoded `SyncChange`: a snapshot of the record at the time of the change.
    var payload: Data
    var createdAt: Date

    init(change: SyncChange, recordID: UUID) throws {
        self.kind = change.kind.rawValue
        self.recordID = recordID
        self.payload = try JSONEncoder().encode(change)
        self.createdAt = .now
    }

    var change: SyncChange? { try? JSONDecoder().decode(SyncChange.self, from: payload) }
}

/// The wire format for one change, sent to the Apps Script and stored in `PendingChange.payload`.
struct SyncChange: Codable {
    enum Kind: String, Codable { case expense, category }
    enum Op: String, Codable { case upsert, delete }

    var kind: Kind
    var op: Op
    var id: String
    var updatedAt: String

    // Expense fields
    var date: String?
    var category: String?
    var categoryId: String?
    var amount: String?
    var note: String?

    // Category fields
    var name: String?
    var icon: String?
    var sortOrder: Int?
    var hidden: Bool?
}

/// Shared date formats for the sheet: day-only dates and precise timestamps.
enum SyncFormat {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// UTC with milliseconds, e.g. "2026-11-24T18:02:11.482Z". Same format the Apps Script writes.
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func timestamp(_ date: Date) -> String { iso.string(from: date) }

    static func parseTimestamp(_ string: String) -> Date? {
        iso.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// Plain "42.18" text, independent of the phone's region settings.
    static func amount(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
    }
}
