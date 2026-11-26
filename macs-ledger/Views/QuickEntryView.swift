import SwiftUI
import SwiftData

struct QuickEntryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]

    @State private var amount: String = ""
    @State private var selectedCategory: Category?
    @State private var errorMessage: String?
    @FocusState private var isAmountFocused: Bool

    private let accent = Color.appAccent
    private let month: Month
    private let onDismiss: (() -> Void)?

    init(month: Month = .current, onDismiss: (() -> Void)? = nil) {
        self.month = month
        self.onDismiss = onDismiss
        let key = month.key
        _monthExpenses = Query(filter: #Predicate<Expense> { $0.monthKey == key })
    }

    private var monthlyTotal: Decimal {
        monthExpenses.reduce(0) { $0 + $1.amount }
    }

    private var categoryTotal: Decimal {
        selectedCategory?.total(for: month) ?? 0
    }

    private var parsedAmount: Decimal? {
        let value = Decimal(string: amount, locale: .current)
        guard let value, value > 0 else { return nil }
        return value
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isAmountFocused = false
                    onDismiss?()
                }

            panel
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 28,
                        topTrailingRadius: 28,
                        style: .continuous
                    )
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
                    .ignoresSafeArea(edges: .bottom) // extends behind the keyboard so its rounded corners show white
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .fontDesign(.rounded)
        .tint(accent)
        .onAppear {
            try? LedgerStore.seedDefaultsIfNeeded(in: context)
            isAmountFocused = true
        }
        .onChange(of: categories, initial: true) {
            if selectedCategory == nil || !categories.contains(where: { $0 == selectedCategory }) {
                selectedCategory = categories.first
            }
        }
        .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // Panel
    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            grabber
            amountRow
            categoryChips
            statsLine
            addButton
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color(UIColor.tertiaryLabel))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    // Amount input
    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("0.00", text: $amount)
                    .font(.system(size: 42, weight: .semibold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Date.now, format: .dateTime.month(.abbreviated).day())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    // Category chips
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    CategoryChip(
                        title: category.name,
                        icon: category.icon,
                        isSelected: category == selectedCategory,
                        accent: accent
                    ) {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    // Compact stats
    private var statsLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(selectedCategory?.name ?? "—")
                    .fontWeight(.semibold)
                Text(categoryTotal, format: .currency(code: "CAD"))
                    .foregroundStyle(Color.appAccentText)
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            ProgressView(value: categoryShare)
                .tint(accent)
        }
    }

    /// Selected category's share of this month's spending
    private var categoryShare: Double {
        guard monthlyTotal > 0 else { return 0 }
        return min(NSDecimalNumber(decimal: categoryTotal / monthlyTotal).doubleValue, 1)
    }

    // MARK: - Button
    private var addButton: some View {
        Button(action: saveEntry) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                Text("Add Expense")
            }
            .font(.headline)
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(canSave ? 1 : 0.4))
            )
        }
        .disabled(!canSave)
        .animation(.easeOut(duration: 0.2), value: canSave)
    }

    private var canSave: Bool { parsedAmount != nil && selectedCategory != nil }

    // Actions
    private func saveEntry() {
        guard let value = parsedAmount, let category = selectedCategory else { return }
        do {
            let date = month == .current ? Date.now : month.startDate
            try LedgerStore.addExpense(amount: value, category: category, date: date, in: context)
            amount = ""
            isAmountFocused = false
            onDismiss?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    QuickEntryView()
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
