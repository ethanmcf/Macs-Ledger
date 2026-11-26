import SwiftUI

/// Shown once when the app launches: the logo's tiles pop in one by one, the name fades in,
/// then everything fades away to reveal the app (about 1.2 seconds).
struct SplashView: View {
    /// Called when the animation has finished and the splash should be removed.
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0
    @State private var showsName = false
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            // Same as the system launch screen, so the handoff from it is seamless.
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                LogoMark(revealed: revealed)
                    .frame(width: 96, height: 96)
                Text("Mac's Ledger")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .opacity(showsName ? 1 : 0)
                    .offset(y: showsName ? 0 : 8)
            }
            .scaleEffect(isLeaving ? 1.08 : 1)
        }
        .opacity(isLeaving ? 0 : 1)
        .task { await play() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac's Ledger, loading")
    }

    private func play() async {
        if reduceMotion {
            // No popping or scaling: show the finished logo, then fade.
            revealed = LogoMark.Tile.all.count
            showsName = true
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeOut(duration: 0.25)) { isLeaving = true }
            try? await Task.sleep(for: .milliseconds(250))
            onFinished()
            return
        }

        try? await Task.sleep(for: .milliseconds(120))
        for count in 1...LogoMark.Tile.all.count {
            revealed = count // each tile springs in (animation lives in LogoMark)
            try? await Task.sleep(for: .milliseconds(70))
        }
        withAnimation(.easeOut(duration: 0.3)) { showsName = true }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true }
        try? await Task.sleep(for: .milliseconds(300))
        onFinished()
    }
}

#Preview {
    SplashView {}
}
