import SwiftUI

/// One category's spending for a period.
struct CategoryTotal: Identifiable {
    /// The category's document ID.
    let id: String
    let name: String
    let icon: String
    let amount: Decimal

    /// Spending per category for the given expenses, largest first. Only categories with spending.
    static func totals(for expenses: some Sequence<Expense>, in store: LedgerStore) -> [CategoryTotal] {
        var sums: [String: (category: Category, amount: Decimal)] = [:]
        for expense in expenses {
            guard let category = store.category(id: expense.categoryId) else { continue }
            sums[category.id, default: (category, 0)].amount += expense.amount
        }
        return sums.values
            .filter { $0.amount > 0 }
            .map { CategoryTotal(id: $0.category.id, name: $0.category.name, icon: $0.category.icon, amount: $0.amount) }
            .sorted { $0.amount > $1.amount }
    }
}

/// Rows of icon, name and amount, each with a bar showing its share of `total`.
struct CategoryBreakdownRows: View {
    let items: [CategoryTotal]
    let total: Decimal
    var currencyCode = "CAD"

    private let accent = Color.appAccent

    var body: some View {
        ForEach(items) { item in
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.footnote)
                        .foregroundStyle(accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(accent.opacity(0.12)))
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(item.amount, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                }
                .monospacedDigit()
                ProgressView(value: total > 0 ? (item.amount / total).doubleValue : 0)
                    .tint(accent)
                    .padding(.leading, 38)
            }
        }
    }
}

/// "Total" label and amount, shown under a breakdown.
struct BreakdownTotalRow: View {
    let total: Decimal
    var currencyCode = "CAD"

    var body: some View {
        HStack {
            Text("Total")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(total, format: .currency(code: currencyCode))
                .font(.headline)
                .monospacedDigit()
        }
    }
}

/// Rounded card with a title, used for dashboard sections.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

/// "Show N more" / "Show less" toggle for a truncated list.
struct ExpandButton: View {
    @Binding var isExpanded: Bool
    let hiddenCount: Int

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? "Show less" : "Show \(hiddenCount) more")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
    }
}

/// Placeholder text inside a card that has nothing to show yet.
struct EmptyCardMessage: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
