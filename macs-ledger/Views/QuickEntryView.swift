import SwiftUI
import SwiftData

struct QuickEntryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var expenses: [Expense]

    @State private var amount: String = ""
    @State private var selectedCategory: Category?
    @State private var errorMessage: String?
    @FocusState private var isAmountFocused: Bool

    private let accent = Color.indigo

    private var thisMonth: DateInterval { .month() }

    private var monthlyTotal: Decimal {
        expenses
            .filter { thisMonth.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var categoryTotal: Decimal {
        selectedCategory?.total(in: thisMonth) ?? 0
    }

    private var parsedAmount: Decimal? {
        let value = Decimal(string: amount, locale: .current)
        guard let value, value > 0 else { return nil }
        return value
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Dimmed backdrop — tap to dismiss the keyboard
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { isAmountFocused = false }

                panel
                    .frame(height: geometry.size.height / 3)
                    .frame(maxWidth: .infinity)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 28,
                            topTrailingRadius: 28,
                            style: .continuous
                        )
                        .fill(Color(UIColor.systemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 20, y: -4)
                        .ignoresSafeArea(.container, edges: .bottom)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .fontDesign(.rounded)
        .tint(accent)
        .onAppear {
            try? LedgerStore.seedDefaultsIfNeeded(in: context)
            isAmountFocused = true
        }
        .onChange(of: categories, initial: true) {
            // Keep a valid selection when categories load, are added or deleted
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

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Grabber
            Capsule()
                .fill(Color(UIColor.tertiaryLabel))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            // Title + amount
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

            // Category chips
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

            // Compact stats
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(selectedCategory?.name ?? "—")
                        .fontWeight(.semibold)
                    Text(categoryTotal, format: .currency(code: "USD"))
                        .foregroundStyle(accent)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("of")
                        .foregroundStyle(.secondary)
                    Text(monthlyTotal, format: .currency(code: "USD"))
                        .foregroundStyle(.secondary)
                    Text("this month")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                ProgressView(value: monthlyTotal > 0 ? min(NSDecimalNumber(decimal: categoryTotal / monthlyTotal).doubleValue, 1) : 0)
                    .tint(accent)
            }

            Spacer(minLength: 0)

            addButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
            .foregroundStyle(.white)
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

    // MARK: - Actions

    private func saveEntry() {
        guard let value = parsedAmount, let category = selectedCategory else { return }
        do {
            try LedgerStore.addExpense(amount: value, category: category, in: context)
            amount = ""
            isAmountFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                Capsule().fill(isSelected ? accent : Color(UIColor.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickEntryView()
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
