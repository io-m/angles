import SwiftUI

@main
struct AnglesApp: App {
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .modifier(UserAppearance(store: themeStore))
        }
    }
}

struct AppRoot: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var isComposePresented = false
    @State private var selectedTab: RootTab = .profile
    @State private var lastContentTab: RootTab = .profile
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(safeAreaInsets: homeSafeAreaInsets)
                }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(RootTab.home)

                Color.clear
                    .tabItem { Label("Inspire me", systemImage: "sparkle") }
                    .tag(RootTab.compose)

                NavigationStack {
                    ProfileView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel,
                        onInspire: presentCompose
                    )
                }
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(RootTab.profile)
            }
            .tint(theme.ink)
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)

            ComposeFrost()
                .opacity(isComposePresented ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .animation(ComposeMotion.fade(reduceMotion), value: isComposePresented)

            ComposeSheetView(
                viewModel: viewModel,
                isActive: isComposePresented,
                onClose: {
                    isComposePresented = false
                },
                onSave: {
                    lastContentTab = .profile
                    selectedTab = .profile
                }
            )
            .opacity(isComposePresented ? 1 : 0)
            .animation(
                ComposeMotion.contentFade(reduceMotion, presented: isComposePresented),
                value: isComposePresented
            )
            .allowsHitTesting(isComposePresented)
            .accessibilityHidden(!isComposePresented)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        captureHomeInsets(geo.safeAreaInsets)
                    }
                    .onChange(of: geo.safeAreaInsets) { _, newInsets in
                        captureHomeInsets(newInsets)
                    }
            }
            .ignoresSafeArea(.keyboard)
        }
    }

    private func handleTabChange(_ newTab: RootTab) {
        if newTab == .compose {
            presentCompose()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = lastContentTab
            }
            return
        }

        lastContentTab = newTab
    }

    private func presentCompose() {
        guard !isComposePresented else {
            return
        }

        viewModel.resetCompose()
        isComposePresented = true
    }

    /// Keyboard bottom inset is hundreds of points; the home indicator is not.
    private func captureHomeInsets(_ insets: EdgeInsets) {
        var next = insets
        if next.bottom > 80 {
            next.bottom = homeSafeAreaInsets.bottom
        }
        homeSafeAreaInsets = next
    }
}
