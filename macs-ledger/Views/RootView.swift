import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var presenter = QuickEntryPresenter.shared
    @State private var page: Page = .dashboard

    private let accent = Color.appAccent

    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case transactions = "Transactions"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            // Both pages stay loaded and are only shown or hidden, so switching doesn't rebuild
            // them (which redrew the toolbar) and each keeps its scroll position.
            ZStack {
                pageView(DashboardView(), for: .dashboard)
                pageView(TransactionsView(), for: .transactions)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Page", selection: $page) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .overlay(alignment: .bottomTrailing) { addButton }
        }
        .fontDesign(.rounded)
        .tint(accent)
        .overlay {
            if presenter.isPresented {
                QuickEntryView(month: .current) {
                    withAnimation(.snappy) { presenter.isPresented = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: presenter.isPresented)
        .onAppear { try? LedgerStore.seedDefaultsIfNeeded(in: context) }
    }

    /// Shows the page only when it's selected, without removing it from the screen.
    private func pageView(_ view: some View, for target: Page) -> some View {
        let isVisible = page == target
        return view
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }

    private var addButton: some View {
        Button {
            withAnimation(.snappy) { presenter.isPresented = true }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(accent))
                .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
        }
        .padding(20)
        .accessibilityLabel("Add expense")
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Category.self, Expense.self], inMemory: true)
}
