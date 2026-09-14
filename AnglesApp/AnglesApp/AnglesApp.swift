import SwiftUI

private enum PaywallPresentationPhase: Equatable {
    case idle
    case locked
}

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
    @State private var storeKitManager = StoreKitManager()
    @State private var isComposePresented = false
    @State private var isOnboardingTasteSession = false
    @State private var hasRoutedLaunch = false
    @State private var selectedTab: RootTab = .home
    @State private var lastContentTab: RootTab = .home
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var pageWidth: CGFloat = 393
    @State private var paywallPhase: PaywallPresentationPhase = .idle
    @State private var paywallShowsCelebration = false
    @State private var paywallHeroCard: HomeCard?
    @State private var isRevealingHome = false
    @AppStorage("hasCompletedOnboardingTaste") private var hasCompletedTaste = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel,
                        storeKitManager: storeKitManager,
                        onLogOut: logOut
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
            .opacity(showsHomeFeed ? 1 : 0)
            .allowsHitTesting(showsHomeFeed)
            .accessibilityHidden(!showsHomeFeed)
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)

            ComposeFrost()
                .opacity(showsCoveringFrost ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .animation(hasRoutedLaunch ? coveringFrostAnimation : nil, value: showsCoveringFrost)

            ComposeSheetView(
                viewModel: viewModel,
                isActive: isComposePresented,
                isOnboardingTaste: isOnboardingTasteSession,
                storeKitManager: storeKitManager,
                onClose: handleComposeClose,
                onSave: handleSavedCard
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

            if paywallPhase == .locked {
                PaywallView(
                    storeKitManager: storeKitManager,
                    showsCelebration: paywallShowsCelebration,
                    savedCard: paywallHeroCard
                )
                    .id(paywallShowsCelebration ? "paywall-celebrate" : "paywall-locked")
                    .transition(.identity)
                    .zIndex(20)
            }

            Group {
                if storeKitManager.isBusy {
                    CheckoutLockOverlay(message: storeKitManager.checkoutLockMessage)
                        .transition(.opacity)
                }
            }
            .animation(coveringFrostAnimation, value: storeKitManager.isBusy)
            .zIndex(25)

            if !hasRoutedLaunch {
                theme.paper
                    .ignoresSafeArea()
                    .zIndex(30)
                    .accessibilityHidden(true)
            }
        }
        .task {
            migrateLegacyPaywallFlag()
            await storeKitManager.prepare()
            withoutAnimations {
                applyGate()
                hasRoutedLaunch = true
            }
        }
        .onChange(of: hasCompletedTaste) { _, completed in
            if completed {
                applyGate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A subscription can lapse while the app is alive. Ask Apple again on every
            // foreground so Home cannot outlive the entitlement until the next cold launch.
            guard phase == .active,
                  storeKitManager.entitlementsReady,
                  !storeKitManager.isBusy else {
                return
            }
            Task {
                await storeKitManager.refreshEntitlements()
                await storeKitManager.probeSubscriptionOffer()
            }
        }
        .onChange(of: storeKitManager.hasUnlockedFullApp) { _, _ in
            guard storeKitManager.entitlementsReady else {
                return
            }
            applyGate()
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            guard isOnboardingTasteSession, isComposePresented else {
                return
            }
            if case .ready = newPhase {
                hasCompletedTaste = true
            }
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

    /// Home chrome stays invisible unless this is the real destination.
    /// Paper/paywall/taste sit on top; a cover gap must never reveal the feed.
    private var showsHomeFeed: Bool {
        hasRoutedLaunch
            && storeKitManager.hasUnlockedFullApp
            && paywallPhase == .idle
            && !isComposePresented
    }

    private var showsCoveringFrost: Bool {
        isComposePresented
            || isRevealingHome
            || paywallPhase == .locked
    }

    private var coveringFrostAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.35)
    }

    private var needsOnboardingTaste: Bool {
        !hasCompletedTaste && !storeKitManager.hasUnlockedFullApp
    }

    private func withoutAnimations(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private func migrateLegacyPaywallFlag() {
        if !hasCompletedTaste, UserDefaults.standard.bool(forKey: "hasEnteredPaywallFlow") {
            hasCompletedTaste = true
        }
        UserDefaults.standard.removeObject(forKey: "hasEnteredPaywallFlow")
    }

    /// Single destination for launch, entitlements, logout, and taste-complete.
    /// Home only when StoreKit says unlocked. Paywall only when taste is done and locked.
    /// Taste compose stays up until Save or Close.
    private func applyGate() {
        guard storeKitManager.entitlementsReady else {
            return
        }

        if storeKitManager.hasUnlockedFullApp {
            if hasRoutedLaunch,
               !storeKitManager.isBusy,
               (paywallPhase == .locked || isComposePresented) {
                return
            }
            revealHome()
            return
        }

        if paywallPhase == .locked {
            return
        }

        if isComposePresented, isOnboardingTasteSession {
            return
        }

        if hasCompletedTaste {
            withoutAnimations {
                isComposePresented = false
                isOnboardingTasteSession = false
                isRevealingHome = false
                paywallPhase = .locked
            }
            return
        }

        withoutAnimations {
            paywallPhase = .idle
            isRevealingHome = false
            presentCompose()
        }
    }

    private func revealHome() {
        hasCompletedTaste = true
        isOnboardingTasteSession = false
        paywallShowsCelebration = false
        paywallHeroCard = nil

        let wasCovered = isComposePresented
            || isRevealingHome
            || paywallPhase == .locked

        withoutAnimations {
            isComposePresented = false
            paywallPhase = .idle
            isRevealingHome = false
        }

        if wasCovered, storeKitManager.isBusy {
            Task { @MainActor in
                await Task.yield()
                withAnimation(coveringFrostAnimation) {
                    storeKitManager.releaseCheckoutLock()
                }
            }
            return
        }

        storeKitManager.releaseCheckoutLock()
    }

    private func logOut() {
        withoutAnimations {
            hasCompletedTaste = false
            paywallShowsCelebration = false
            paywallHeroCard = nil
            paywallPhase = .idle
            viewModel.resetCompose()
            isOnboardingTasteSession = false
            isRevealingHome = true
            storeKitManager.signOut()
            presentCompose()
            isRevealingHome = false
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

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.resetCompose()
        isOnboardingTasteSession = needsOnboardingTaste
        if isOnboardingTasteSession {
            viewModel.composeIsPublic = false
            storeKitManager.clearError()
        }
        isComposePresented = true
    }

    private func handleComposeClose() {
        let finishOnboarding = isOnboardingTasteSession && viewModel.isCookReady
        isOnboardingTasteSession = false

        if finishOnboarding, !storeKitManager.hasUnlockedFullApp, paywallPhase == .idle {
            hasCompletedTaste = true
            paywallShowsCelebration = false
            withoutAnimations {
                paywallPhase = .locked
            }
        }

        isComposePresented = false
    }

    private func handleSavedCard(_ card: HomeCard) {
        guard isOnboardingTasteSession else {
            lastContentTab = .profile
            selectedTab = .profile
            return
        }

        lastContentTab = .home
        selectedTab = .home
        paywallHeroCard = card
        paywallShowsCelebration = true
        withoutAnimations {
            paywallPhase = .locked
        }
        hasCompletedTaste = true
        withAnimation(coveringFrostAnimation) {
            isComposePresented = false
        }
        isOnboardingTasteSession = false
    }

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
