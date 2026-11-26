import Foundation
import Network
import Observation
import SwiftData

/// Sends queued changes (`PendingChange`) to the Google Sheet's Apps Script, and pulls the sheet back
/// into the app on request. Everything runs on the main actor; only the network calls suspend.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    // MARK: State shown in Settings › Backup
    private(set) var isSyncing = false
    private(set) var pendingCount = 0
    private(set) var lastError: String?
    private(set) var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: Keys.lastSyncedAt) as? Date {
        didSet { UserDefaults.standard.set(lastSyncedAt, forKey: Keys.lastSyncedAt) }
    }

    // MARK: Configuration (Keychain)
    var webAppURL: String { Keychain.string(for: Keys.url) ?? "" }
    var token: String { Keychain.string(for: Keys.token) ?? "" }
    var isConfigured: Bool { URL(string: webAppURL)?.scheme == "https" && !token.isEmpty }

    func saveConfiguration(url: String, token: String) {
        Keychain.set(url.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.url)
        Keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), for: Keys.token)
        lastError = nil
    }

    private enum Keys {
        static let url = "webAppURL"
        static let token = "token"
        static let lastSyncedAt = "backup.lastSyncedAt"
    }

    private var container: ModelContainer?
    private var debounce: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private let batchSize = 200

    /// Automatic retries after a network failure, waiting longer each time (the last delay repeats).
    private var retry: Task<Void, Never>?
    private var retryAttempt = 0
    private let retryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(30), .seconds(60), .seconds(120), .seconds(300)]

    /// Requests made while offline wait for the connection instead of failing immediately, up to the
    /// resource timeout. Then the retry schedule takes over.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    private var context: ModelContext? { container?.mainContext }

    // MARK: - Lifecycle

    /// Call once at launch with the app's container.
    func start(container: ModelContainer) {
        self.container = container
        if let context { try? LedgerStore.prepareForSync(in: context) }
        refreshPendingCount()
        // When the connection comes back, send anything that queued up while offline. Wait a moment first:
        // the network is often reported "up" a little before requests actually go through.
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                let sync = SyncService.shared
                sync.retryAttempt = 0
                sync.scheduleSync(after: .seconds(2))
            }
        }
        monitor.start(queue: DispatchQueue(label: "macs-ledger.network"))
    }

    /// Sends queued changes shortly. Bursts of changes (e.g. an import) are coalesced into one send.
    func scheduleSync(after delay: Duration = .seconds(2)) {
        refreshPendingCount()
        guard isConfigured else { return }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    func refreshPendingCount() {
        pendingCount = (try? context?.fetchCount(FetchDescriptor<PendingChange>())) ?? 0
    }

    // MARK: - Push (app → sheet)

    /// Sends queued changes oldest-first in batches. A batch is removed from the queue only after the sheet
    /// confirms it; on any failure the rest stays queued for the next attempt.
    func push() async {
        guard let context, isConfigured, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false; refreshPendingCount() }

        do {
            while true {
                var descriptor = FetchDescriptor<PendingChange>(sortBy: [SortDescriptor(\.createdAt)])
                descriptor.fetchLimit = batchSize
                let batch = try context.fetch(descriptor)
                guard !batch.isEmpty else { break }

                let sentIDs = Set(batch.map(\.persistentModelID))
                let changes = batch.compactMap(\.change)
                if !changes.isEmpty {
                    let response: AckResponse = try await send(PushRequest(token: token, changes: changes))
                    guard response.ok else { throw SyncError.server(response.error ?? "The sheet rejected the backup.") }
                }

                // Re-fetch: changes recorded during the request may have replaced some of these entries.
                for pending in try context.fetch(FetchDescriptor<PendingChange>()) where sentIDs.contains(pending.persistentModelID) {
                    context.delete(pending)
                }
                try context.save()
                lastSyncedAt = .now
            }
            lastError = nil
            retryAttempt = 0
            retry?.cancel()
        } catch {
            lastError = error.localizedDescription
            if Self.isNetworkProblem(error) { scheduleRetry() }
        }
    }

    /// Tries again later after a network failure. Not used for problems retrying won't fix (wrong token,
    /// wrong URL); those wait for the user to fix the settings.
    private func scheduleRetry() {
        guard isConfigured, (try? context?.fetchCount(FetchDescriptor<PendingChange>())) ?? 0 > 0 else { return }
        let delay = retryDelays[min(retryAttempt, retryDelays.count - 1)]
        retryAttempt += 1
        retry?.cancel()
        retry = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await push()
        }
    }

    private static func isNetworkProblem(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
             .secureConnectionFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// Queues every category and expense, then sends them. Used for the first backup.
    func backupEverything() async {
        guard let context else { return }
        do {
            for category in try context.fetch(FetchDescriptor<Category>()) {
                try LedgerStore.recordChange(.upsert, category, in: context)
            }
            for expense in try context.fetch(FetchDescriptor<Expense>()) {
                try LedgerStore.recordChange(.upsert, expense, in: context)
            }
            try context.save()
            refreshPendingCount()
            await push()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Pull (sheet → app)

    struct PullSummary {
        var added = 0
        var updated = 0
        var deleted = 0
        /// Categories deleted in the sheet that still had expenses in the app, so they were hidden instead.
        var keptHidden: [String] = []
        var description: String {
            var text = added + updated + deleted == 0
                ? "Already up to date."
                : "\(added) added, \(updated) updated, \(deleted) removed."
            if !keptHidden.isEmpty {
                text += "\n\n\(keptHidden.joined(separator: ", ")) still \(keptHidden.count == 1 ? "has" : "have") expenses, so \(keptHidden.count == 1 ? "it was" : "they were") hidden instead of deleted. Delete \(keptHidden.count == 1 ? "it" : "them") in Settings › Categories to choose what happens to the expenses."
            }
            return text
        }
    }

    /// Downloads the sheet and merges it in. For each record the newer `updatedAt` wins. Records with
    /// changes still waiting to upload are left alone (the app's version is newer). Records that exist
    /// in the app but not in the sheet are queued for upload, so the sheet is repaired, never trusted to delete
    /// by omission. A row is only deleted when the sheet marks it `deleted`.
    func pull() async throws -> PullSummary {
        guard let context, isConfigured else { throw SyncError.notConfigured }
        guard !isSyncing else { throw SyncError.busy }

        // Send local changes first so the sheet is current, then read it back.
        // (push() manages isSyncing itself, so mark busy only after it finishes.)
        debounce?.cancel()
        await push()
        if let lastError { throw SyncError.server(lastError) }

        isSyncing = true
        defer { isSyncing = false; refreshPendingCount() }

        var components = URLComponents(string: webAppURL)
        components?.queryItems = [URLQueryItem(name: "action", value: "export"), URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else { throw SyncError.notConfigured }
        let export: ExportResponse = try await get(url)
        guard export.ok else { throw SyncError.server(export.error ?? "The sheet refused the request.") }

        var summary = PullSummary()
        let pendingIDs = Set(try context.fetch(FetchDescriptor<PendingChange>()).map(\.recordID))

        // Categories
        var categories = try context.fetch(FetchDescriptor<Category>())
        var categoryByID: [UUID: Category] = [:]
        for category in categories { if let id = category.uuid { categoryByID[id] = category } }

        // Categories the sheet marks deleted. Handled after expenses are merged, because the same update
        // may move or delete their expenses.
        var deletedInSheet: [Category] = []

        for remote in export.categories {
            guard let id = UUID(uuidString: remote.id), !pendingIDs.contains(id) else { continue }
            let remoteDate = SyncFormat.parseTimestamp(remote.updatedAt) ?? .distantPast

            if let local = categoryByID[id] {
                guard remoteDate > (local.updatedAt ?? .distantPast) else { continue }
                if remote.deleted {
                    deletedInSheet.append(local)
                } else if apply(remote, to: local, among: categories) {
                    local.updatedAt = remoteDate
                    summary.updated += 1
                }
            } else if !remote.deleted {
                // Same name, different ID (e.g. the starter categories after a reinstall): adopt the sheet's ID.
                if let sameName = categories.first(where: { $0.name.caseInsensitiveCompare(remote.name) == .orderedSame && !pendingIDs.contains($0.uuid ?? UUID()) }) {
                    if let oldID = sameName.uuid { categoryByID[oldID] = nil }
                    sameName.uuid = id
                    _ = apply(remote, to: sameName, among: categories)
                    sameName.updatedAt = remoteDate
                    categoryByID[id] = sameName
                    summary.updated += 1
                } else {
                    let category = Category(name: remote.name, icon: remote.icon, sortOrder: remote.sortOrder)
                    category.uuid = id
                    category.isHidden = remote.hidden
                    category.updatedAt = remoteDate
                    context.insert(category)
                    categories.append(category)
                    categoryByID[id] = category
                    summary.added += 1
                }
            }
        }

        /// The category for a sheet row: by ID, then by name, otherwise a new category.
        func resolveCategory(id: String?, name: String) throws -> Category? {
            if let id = id.flatMap(UUID.init(uuidString:)), let match = categoryByID[id] { return match }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let match = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return match }
            let created = Category(name: trimmed, icon: CSVImport.guessIcon(for: trimmed),
                                   sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(created)
            categories.append(created)
            if let id = created.uuid { categoryByID[id] = created }
            try LedgerStore.recordChange(.upsert, created, in: context)
            return created
        }

        // Expenses
        var expenseByID: [UUID: Expense] = [:]
        for expense in try context.fetch(FetchDescriptor<Expense>()) { if let id = expense.uuid { expenseByID[id] = expense } }

        for remote in export.expenses {
            guard let id = UUID(uuidString: remote.id), !pendingIDs.contains(id) else { continue }
            let remoteDate = SyncFormat.parseTimestamp(remote.updatedAt) ?? .distantPast
            let local = expenseByID[id]

            if remote.deleted {
                if let local, remoteDate > (local.updatedAt ?? .distantPast) {
                    context.delete(local)
                    expenseByID[id] = nil
                    summary.deleted += 1
                }
                continue
            }
            guard let amount = Decimal(string: remote.amount, locale: Locale(identifier: "en_US_POSIX")), amount > 0,
                  let day = SyncFormat.day.date(from: remote.date) else { continue }
            let category = try resolveCategory(id: remote.categoryId, name: remote.category)

            if let local {
                guard remoteDate > (local.updatedAt ?? .distantPast) else { continue }
                // Keep the local time of day if the calendar day didn't change.
                if !Calendar.current.isDate(local.date, inSameDayAs: day) { local.date = day }
                local.amount = amount
                local.monthKey = Month(containing: local.date).key
                local.note = remote.note
                local.category = category
                local.updatedAt = remoteDate
                summary.updated += 1
            } else {
                let expense = Expense(amount: amount, category: category, date: day, note: remote.note)
                expense.uuid = id
                expense.updatedAt = remoteDate
                context.insert(expense)
                expenseByID[id] = expense
                summary.added += 1
            }
        }

        // Apply category deletions from the sheet. A category with no expenses left is deleted. One that still
        // has expenses is hidden instead, so they don't become uncategorized. That's sent back to the sheet as
        // hidden = TRUE, deleted = FALSE, so both sides agree.
        for category in deletedInSheet {
            if category.expenses.isEmpty {
                if let id = category.uuid { categoryByID[id] = nil }
                categories.removeAll { $0 == category }
                context.delete(category)
                summary.deleted += 1
            } else {
                category.isHidden = true
                try LedgerStore.recordChange(.upsert, category, in: context)
                summary.keptHidden.append(category.name)
            }
        }

        // Anything the sheet is missing gets queued for upload.
        let remoteCategoryIDs = Set(export.categories.compactMap { UUID(uuidString: $0.id) })
        for (id, category) in categoryByID where !remoteCategoryIDs.contains(id) && !pendingIDs.contains(id) && category.updatedAt != nil {
            try LedgerStore.recordChange(.upsert, category, in: context)
        }
        let remoteExpenseIDs = Set(export.expenses.compactMap { UUID(uuidString: $0.id) })
        for (id, expense) in expenseByID where !remoteExpenseIDs.contains(id) && !pendingIDs.contains(id) {
            try LedgerStore.recordChange(.upsert, expense, in: context)
        }

        try context.save()
        lastSyncedAt = .now
        scheduleSync(after: .zero)
        return summary
    }

    /// Copies a sheet category onto a local one. Skips a rename that would clash with another category's name.
    /// Returns whether anything changed.
    private func apply(_ remote: RemoteCategory, to local: Category, among categories: [Category]) -> Bool {
        var changed = false
        let nameTaken = categories.contains { $0 != local && $0.name.caseInsensitiveCompare(remote.name) == .orderedSame }
        if !remote.name.isEmpty, remote.name != local.name, !nameTaken { local.name = remote.name; changed = true }
        if !remote.icon.isEmpty, remote.icon != local.icon { local.icon = remote.icon; changed = true }
        if remote.sortOrder != local.sortOrder { local.sortOrder = remote.sortOrder; changed = true }
        if remote.hidden != local.isHidden { local.isHidden = remote.hidden; changed = true }
        return changed
    }

    // MARK: - Networking

    private struct PushRequest: Encodable {
        let token: String
        let changes: [SyncChange]
    }

    private struct AckResponse: Decodable {
        let ok: Bool
        let error: String?
    }

    struct RemoteCategory: Decodable {
        let id: String
        let name: String
        let icon: String
        let sortOrder: Int
        let hidden: Bool
        let updatedAt: String
        let deleted: Bool
    }

    struct RemoteExpense: Decodable {
        let id: String
        let date: String
        let category: String
        let categoryId: String?
        let amount: String
        let note: String
        let updatedAt: String
        let deleted: Bool
    }

    private struct ExportResponse: Decodable {
        let ok: Bool
        let error: String?
        let categories: [RemoteCategory]
        let expenses: [RemoteExpense]

        enum CodingKeys: CodingKey { case ok, error, categories, expenses }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ok = try c.decode(Bool.self, forKey: .ok)
            error = try c.decodeIfPresent(String.self, forKey: .error)
            categories = try c.decodeIfPresent([RemoteCategory].self, forKey: .categories) ?? []
            expenses = try c.decodeIfPresent([RemoteExpense].self, forKey: .expenses) ?? []
        }
    }

    enum SyncError: LocalizedError {
        case notConfigured
        case busy
        case server(String)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Add your web app URL and token in Settings › Backup."
            case .busy: "A backup is already running. Try again in a moment."
            case .server(let message): message
            case .unexpectedResponse:
                "The sheet sent back something unexpected. Check the web app URL, and that the deployment's access is set to “Anyone”."
            }
        }
    }

    private func send<Response: Decodable>(_ body: some Encodable) async throws -> Response {
        guard let url = URL(string: webAppURL) else { throw SyncError.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        // Apps Script reads the raw body; text/plain avoids an extra CORS-style preflight on Google's side.
        request.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // Apps Script answers with a redirect to script.googleusercontent.com; URLSession follows it.
        let (data, _) = try await session.data(for: request)
        return try decode(data)
    }

    private func get<Response: Decodable>(_ url: URL) async throws -> Response {
        let (data, _) = try await session.data(for: URLRequest(url: url, timeoutInterval: 60))
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // A Google sign-in page or error page comes back as HTML instead of JSON.
            throw SyncError.unexpectedResponse
        }
    }
}
