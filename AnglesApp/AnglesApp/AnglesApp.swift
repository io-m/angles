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
    @State private var viewModel = HomeViewModel()
    @State private var isComposePresented = false
    @State private var selectedTab: RootTab = .profile
    @State private var lastContentTab: RootTab = .profile
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var pageWidth: CGFloat = 393
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel
                    )
                }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(RootTab.home)

                Color.clear
                    .tabItem { Label("Inspire me", systemImage: "sparkle") }
                    .tag(RootTab.compose)

                NavigationStack {
                    ProfileView(
                        safeAreaInsets: homeSafeAreaInsets,
                        pageWidth: pageWidth,
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

            WriteErrorBanner(message: viewModel.writeError) {
                viewModel.dismissWriteError()
            }
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: viewModel.writeError)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        captureHomeInsets(geo.safeAreaInsets)
                        pageWidth = geo.size.width
                    }
                    .onChange(of: geo.safeAreaInsets) { _, newInsets in
                        captureHomeInsets(newInsets)
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        pageWidth = newWidth
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

/// Every card write is optimistic. When one fails the card rolls back on its own, so this
/// is the only thing that says the server was never reached.
private struct WriteErrorBanner: View {
    let message: String?
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack {
            if let message {
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.muted)

                        Text(message)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(theme.surface, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(theme.cardHairline, lineWidth: 1)
                    }
                    .shadow(color: theme.shadowSoft, radius: 10, y: 3)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel(message)
                .accessibilityHint("Dismisses this message")
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }
}
