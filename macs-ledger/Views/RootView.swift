import SwiftUI

struct RootView: View {
    @State private var presenter = QuickEntryPresenter.shared
    @State private var page: Page = .dashboard
    @State private var showsSettings = false
    @State private var showsSplash = true

    private let accent = Color.appAccent

    enum Page: String {
        case dashboard = "Dashboard"
        case history = "History"
        case transactions = "Transactions"
    }

    var body: some View {
        // TabView keeps every page alive, so each one keeps its scroll position and expanded lists.
        TabView(selection: $page) {
            Tab(Page.dashboard.rawValue, systemImage: "chart.pie.fill", value: Page.dashboard) {
                pageStack(DashboardView(), title: Page.dashboard.rawValue)
            }
            Tab(Page.history.rawValue, systemImage: "clock.arrow.circlepath", value: Page.history) {
                pageStack(HistoryView(), title: Page.history.rawValue)
            }
            Tab(Page.transactions.rawValue, systemImage: "list.bullet", value: Page.transactions) {
                pageStack(TransactionsView(), title: Page.transactions.rawValue)
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
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
        .overlay {
            if showsSplash {
                SplashView { showsSplash = false }
            }
        }
        // Opened via Back Tap / the quick entry shortcut: skip the splash and go straight to entry.
        .onChange(of: presenter.isPresented) { _, isPresented in
            if isPresented { showsSplash = false }
        }
    }

    /// One tab's page: its own navigation stack (so tapping a month pushes within the tab), title, settings
    /// button, and the add button floating above the tab bar.
    private func pageStack(_ page: some View, title: String) -> some View {
        NavigationStack {
            page
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { showsSettings = true }
                    }
                }
                .overlay(alignment: .bottomTrailing) { addButton }
        }
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
