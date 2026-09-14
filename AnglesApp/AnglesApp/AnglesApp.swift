import SwiftUI

private enum PaywallPresentationPhase: Equatable {
    case idle
    case cardHold
    case benefits
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
    @State private var selectedTab: RootTab = .home
    @State private var lastContentTab: RootTab = .home
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var pageWidth: CGFloat = 393
    @State private var glimpseCard: HomeCard?
    @State private var paywallPhase: PaywallPresentationPhase = .idle
    @State private var glimpseToken = UUID()
    @AppStorage("hasCompletedOnboardingTaste") private var hasCompletedTaste = false
    @AppStorage("hasEnteredPaywallFlow") private var hasEnteredPaywallFlow = false
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
                        viewModel: viewModel,
                        storeKitManager: storeKitManager,
                        glimpseCard: glimpseCard,
                        isGlimpseActive: isGlimpseActive,
                        onResetOnboarding: resetToOnboarding
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
            .allowsHitTesting(!blocksAppInteraction)
            .accessibilityHidden(blocksAppInteraction)
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

            if paywallPhase == .benefits, !storeKitManager.hasUnlockedFullApp {
                PaywallGlimpseView(
                    safeAreaInsets: homeSafeAreaInsets,
                    onContinue: continueToPaywall
                )
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if paywallPhase == .locked, !storeKitManager.hasUnlockedFullApp {
                PaywallView(storeKitManager: storeKitManager)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .onAppear {
            if needsOnboardingTaste {
                presentCompose()
            } else if !storeKitManager.hasUnlockedFullApp {
                paywallPhase = .locked
            }
        }
        .task {
            await storeKitManager.prepare()
            reconcileSubscriptionGate()
        }
        .onChange(of: hasCompletedTaste) { _, completed in
            if !completed && !isComposePresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if !hasCompletedTaste && !isComposePresented {
                        presentCompose()
                    }
                }
            } else if completed {
                reconcileSubscriptionGate()
            }
        }
        .onChange(of: hasEnteredPaywallFlow) { _, entered in
            if !entered, !isComposePresented {
                presentCompose()
            } else if entered {
                reconcileSubscriptionGate()
            }
        }
        .onChange(of: storeKitManager.hasUnlockedFullApp) { _, _ in
            reconcileSubscriptionGate()
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

    private var isGlimpseActive: Bool {
        paywallPhase == .cardHold || paywallPhase == .benefits
    }

    private var needsOnboardingTaste: Bool {
        !hasCompletedTaste || !hasEnteredPaywallFlow
    }

    private var blocksAppInteraction: Bool {
        isGlimpseActive || (paywallPhase == .locked && !storeKitManager.hasUnlockedFullApp)
    }

    private func resetToOnboarding() {
        glimpseToken = UUID()
        glimpseCard = nil
        paywallPhase = .idle
        storeKitManager.resetForOnboardingTest()
        hasEnteredPaywallFlow = false
        hasCompletedTaste = false
        viewModel.resetCompose()
        isComposePresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            presentCompose()
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
        if needsOnboardingTaste {
            viewModel.composeIsPublic = false
        }
        isComposePresented = true
    }

    private func handleComposeClose() {
        isComposePresented = false
        guard needsOnboardingTaste, viewModel.isCookReady else {
            return
        }

        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            hasCompletedTaste = true
            hasEnteredPaywallFlow = true
            paywallPhase = .locked
        }
    }

    private func handleSavedCard(_ card: HomeCard) {
        guard needsOnboardingTaste else {
            lastContentTab = .profile
            selectedTab = .profile
            return
        }

        let token = UUID()
        glimpseToken = token
        glimpseCard = card
        paywallPhase = .cardHold
        lastContentTab = .home
        selectedTab = .home
        hasCompletedTaste = true
        hasEnteredPaywallFlow = true

        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard glimpseToken == token, !storeKitManager.hasUnlockedFullApp else {
                return
            }

            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                paywallPhase = .benefits
            }
        }
    }

    private func continueToPaywall() {
        guard paywallPhase == .benefits else {
            return
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            glimpseCard = nil
            paywallPhase = .locked
        }
    }

    private func reconcileSubscriptionGate() {
        if storeKitManager.hasUnlockedFullApp {
            glimpseToken = UUID()
            glimpseCard = nil
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                paywallPhase = .idle
            }
        } else if hasCompletedTaste,
                  hasEnteredPaywallFlow,
                  paywallPhase == .idle,
                  !isComposePresented {
            paywallPhase = .locked
        }
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
