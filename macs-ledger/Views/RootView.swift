import SwiftUI

struct RootView: View {
    @State private var presenter = QuickEntryPresenter.shared
    @State private var page: Page = .dashboard
    @State private var showsSettings = false
    @State private var showsSplash = true

    private let accent = Color.appAccent

    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case transactions = "Transactions"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
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
