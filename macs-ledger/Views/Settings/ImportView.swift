import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Pick a CSV of monthly category totals, review how columns map to categories, then import.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var choosingFile = false
    @State private var fileName: String?
    @State private var csv: CSVImport?
    @State private var targets: [Int: CSVImport.Target] = [:]
    @State private var newNames: [Int: String] = [:]
    @State private var year = Calendar.current.component(.year, from: .now) - 1
    @State private var errorMessage: String?
    @State private var importedCount: Int?

    private let currencyCode = "CAD"

    var body: some View {
        Form {
            Section {
                Button(fileName == nil ? "Choose CSV File" : "Choose a Different File", systemImage: "doc") {
                    choosingFile = true
                }
                if let fileName {
                    LabeledContent("File", value: fileName)
                }
            } footer: {
                if csv == nil {
                    Text("""
                    The first row should be headers: Month, then one column per category, and optionally Total. \
                    Each row is one month, like "Jan 2024" or "2024-01". Each category becomes one expense \
                    for that month, dated the 1st. Importing the same months again replaces the earlier import.
                    """)
                }
            }

            if let csv {
                columnsSection(csv)
                if csv.needsYear { yearSection }
                summarySection(csv)
                warningsSection(csv)
            }
        }
        .navigationTitle("Import from CSV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let csv {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { runImport(csv) }
                        .disabled(!canImport(csv))
                }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            load(result)
        }
        .alert("Couldn't import", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Import complete", isPresented: .constant(importedCount != nil)) {
            Button("Done") {
                importedCount = nil
                dismiss()
            }
        } message: {
            Text("Added \(importedCount ?? 0) monthly \(importedCount == 1 ? "total" : "totals").")
        }
    }

    // MARK: - Sections

    private func columnsSection(_ csv: CSVImport) -> some View {
        Section {
            ForEach(csv.categoryColumns) { column in
                VStack(alignment: .leading, spacing: 8) {
                    Picker(selection: targetBinding(column)) {
                        Text("New category").tag(CSVImport.Target.create(newNames[column.index] ?? column.header))
                        ForEach(categories) { category in
                            Text(category.name).tag(CSVImport.Target.existing(category.persistentModelID))
                        }
                        Text("Skip").tag(CSVImport.Target.skip)
                    } label: {
                        Text("“\(column.header)”")
                            .font(.subheadline.weight(.semibold))
                    }
                    if case .create = targets[column.index] {
                        TextField("New category name", text: nameBinding(column))
                            .font(.subheadline)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Columns")
        } footer: {
            Text("Match each column to one of your categories, create a new one (you can fix the name here), or skip it.")
        }
    }

    private var yearSection: some View {
        Section {
            Stepper(value: $year, in: 1990...Calendar.current.component(.year, from: .now)) {
                LabeledContent("Year", value: String(year))
            }
        } footer: {
            Text("Some months in the file don't include a year. They'll be imported into this year.")
        }
    }

    private func summarySection(_ csv: CSVImport) -> some View {
        let planned = csv.plannedAmounts(targets: resolvedTargets, fallbackYear: year)
        let months = Set(planned.map(\.month)).sorted()
        let total = planned.reduce(Decimal(0)) { $0 + $1.amount }
        return Section("Summary") {
            if let first = months.first, let last = months.last {
                LabeledContent("Months", value: first == last ? first.title : "\(first.title) – \(last.title)")
            }
            LabeledContent("Monthly totals to add", value: String(planned.count))
            LabeledContent("Total amount", value: total.formatted(.currency(code: currencyCode)))
        }
    }

    @ViewBuilder
    private func warningsSection(_ csv: CSVImport) -> some View {
        let warnings = warnings(for: csv)
        if !warnings.isEmpty {
            Section {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Check these rows")
            } footer: {
                Text("Rows with an unreadable month are skipped. Everything else still imports.")
            }
        }
    }

    // MARK: - Logic

    private func warnings(for csv: CSVImport) -> [String] {
        csv.rows.flatMap { row -> [String] in
            var list: [String] = []
            let label = row.rawMonth.isEmpty ? "Row \(row.line)" : "Row \(row.line) (\(row.rawMonth))"
            if row.month == .invalid {
                list.append("\(label): “\(row.rawMonth)” isn't a month — skipped.")
            }
            if !row.unreadableCells.isEmpty {
                list.append("\(label): couldn't read \(row.unreadableCells.joined(separator: ", ")) — left out.")
            }
            if row.month != .invalid, row.totalMismatch, let total = row.total {
                let sum = row.amounts.values.reduce(0, +)
                list.append("\(label): categories add up to \(sum.formatted(.currency(code: currencyCode))) but Total says \(total.formatted(.currency(code: currencyCode))).")
            }
            return list
        }
    }

    /// Targets with each "New category" carrying its current (possibly edited) name.
    private var resolvedTargets: [Int: CSVImport.Target] {
        targets.mapValues { $0 }.reduce(into: [:]) { result, entry in
            if case .create = entry.value {
                result[entry.key] = .create(newNames[entry.key] ?? "")
            } else {
                result[entry.key] = entry.value
            }
        }
    }

    private func canImport(_ csv: CSVImport) -> Bool {
        let creatingBlankName = resolvedTargets.values.contains {
            if case .create(let name) = $0 { name.trimmingCharacters(in: .whitespaces).isEmpty } else { false }
        }
        return !creatingBlankName && !csv.plannedAmounts(targets: resolvedTargets, fallbackYear: year).isEmpty
    }

    private func targetBinding(_ column: CSVImport.Column) -> Binding<CSVImport.Target> {
        Binding {
            switch targets[column.index] ?? .skip {
            // The picker's "New category" tag carries the current name, so match it here.
            case .create: .create(newNames[column.index] ?? column.header)
            case let other: other
            }
        } set: { newValue in
            targets[column.index] = newValue
        }
    }

    private func nameBinding(_ column: CSVImport.Column) -> Binding<String> {
        Binding { newNames[column.index] ?? column.header } set: { newNames[column.index] = $0 }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            // Excel on Windows often saves CSV as Windows-1252 rather than UTF-8.
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let parsed = try CSVImport(text: text)
            fileName = url.lastPathComponent
            csv = parsed
            setDefaultTargets(for: parsed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Columns whose header matches a category name (ignoring case) map to it; the rest default
    /// to a new category named after the header, capitalized.
    private func setDefaultTargets(for csv: CSVImport) {
        targets = [:]
        newNames = [:]
        for column in csv.categoryColumns {
            if let match = categories.first(where: { $0.name.caseInsensitiveCompare(column.header) == .orderedSame }) {
                targets[column.index] = .existing(match.persistentModelID)
            } else {
                newNames[column.index] = column.header.capitalized
                targets[column.index] = .create(column.header.capitalized)
            }
        }
    }

    private func runImport(_ csv: CSVImport) {
        do {
            importedCount = try csv.apply(targets: resolvedTargets, fallbackYear: year, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { ImportView() }
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
