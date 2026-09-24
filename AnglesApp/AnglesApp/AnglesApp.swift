import SwiftUI

private enum PaywallPresentationPhase: Equatable {
    case idle
    case locked
}

private enum HomeRevealPhase: Equatable {
    case hidden
    case waitingForCheckout
    case waitingForHome
    case animating
    case visible
}

enum BrowseRoute: Hashable {
    case author(AuthorRoute)
    case model(ModelRoute)
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
    @State private var identityStore = ProfileIdentityStore()
    @State private var isComposePresented = false
    @State private var isOnboardingTasteSession = false
    @State private var hasRoutedLaunch = false
    @State private var selectedTab: RootTab = .home
    @State private var lastContentTab: RootTab = .home
    @State private var browsePath: [BrowseRoute] = []
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var paywallPhase: PaywallPresentationPhase = .idle
    @State private var paywallShowsCelebration = false
    @State private var paywallHeroCard: HomeCard?
    @State private var homeRevealPhase: HomeRevealPhase = .hidden
    @State private var saveCoverLabel: String?
    @State private var saveCoverPresented = false
    @AppStorage("hasCompletedOnboardingTaste") private var hasCompletedTaste = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            NavigationStack(path: $browsePath) {
                TabView(selection: $selectedTab) {
                    HomeView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel,
                        storeKitManager: storeKitManager,
                        isActiveTab: selectedTab == .home,
                        onLogOut: logOut,
                        onOpenAuthor: openAuthor,
                        onOpenModel: openModel
                    )
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(RootTab.home)

                    Color.clear
                        .tabItem { Label("Inspire me", systemImage: "sparkle") }
                        .tag(RootTab.compose)

                    ProfileView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel,
                        storeKitManager: storeKitManager,
                        identityStore: identityStore,
                        onInspire: presentCompose,
                        onLogOut: logOut,
                        canLoadFullAppContent: canLoadProfileContent,
                        onOpenAuthor: openAuthor,
                        onOpenModel: openModel,
                        onOpenFollowed: openFollowed
                    )
                    .tabItem { Label("Profile", systemImage: "person") }
                    .tag(RootTab.profile)
                }
                .navigationDestination(for: BrowseRoute.self) { route in
                    switch route {
                    case .author(let author):
                        AuthorProfileView(
                            route: author,
                            safeAreaInsets: homeSafeAreaInsets,
                            viewModel: viewModel,
                            onOpenAuthor: openAuthor,
                            onOpenModel: openModel
                        )
                        .navigationBarBackButtonHidden(true)
                    case .model(let model):
                        ModelProfileView(
                            route: model,
                            safeAreaInsets: homeSafeAreaInsets,
                            viewModel: viewModel,
                            onOpenAuthor: openAuthor,
                            onOpenModel: openModel
                        )
                        .navigationBarBackButtonHidden(true)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tint(theme.ink)
            .opacity(showsHomeFeed ? 1 : 0)
            .allowsHitTesting(showsHomeFeed && homeRevealPhase == .visible)
            .accessibilityHidden(!showsHomeFeed || homeRevealPhase != .visible)
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)

            theme.paper
                .ignoresSafeArea()
                .opacity(isHomeRevealPending ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ComposeFrost()
                .opacity(showsCoveringFrost ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            ComposeSheetView(
                viewModel: viewModel,
                isActive: isComposePresented,
                isOnboardingTaste: isOnboardingTasteSession,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onClose: handleComposeClose,
                onShowMembership: presentMembershipPaywall,
                onSave: handleSavedCard,
                onPresentSaveCover: presentSaveCover,
                onDismissSaveCover: dismissSaveCover
            )
            .opacity(isComposePresented ? 1 : 0)
            .animation(
                saveCoverPresented
                    ? nil
                    : ComposeMotion.contentFade(reduceMotion, presented: isComposePresented),
                value: isComposePresented
            )
            .allowsHitTesting(isComposePresented)
            .accessibilityHidden(!isComposePresented)

            if let saveCoverLabel {
                GeometryReader { proxy in
                    SaveCelebrationCover(
                        label: saveCoverLabel,
                        playsAnimation: !reduceMotion
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: saveCoverPresented ? 0 : -proxy.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(saveCoverPresented)
                .accessibilityHidden(!saveCoverPresented)
                .zIndex(18)
            }

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
                    .transition(.identity)
                    .zIndex(20)
            }

            if showsHomeArrivalStatus {
                HomeArrivalStatus()
                    .transition(.opacity)
                    .zIndex(24)
            }

            Group {
                if storeKitManager.isBusy {
                    CheckoutLockOverlay(lines: storeKitManager.checkoutLockLines)
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
        .environment(\.profileIdentity, identityStore)
        .task {
            identityStore.onSynced = { initials, avatarPath in
                viewModel.applyOwnerIdentity(initials: initials, avatarPath: avatarPath)
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
        .onChange(of: storeKitManager.isBusy) { _, _ in
            guard storeKitManager.entitlementsReady, storeKitManager.hasUnlockedFullApp else {
                return
            }
            applyGate()
        }
        .onChange(of: viewModel.feedLoadState) { _, _ in
            advanceHomeRevealIfPossible()
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
            || isHomeRevealPending
            || paywallPhase == .locked
    }

    private var isHomeRevealPending: Bool {
        switch homeRevealPhase {
        case .waitingForCheckout, .waitingForHome, .animating:
            return true
        case .hidden, .visible:
            return false
        }
    }

    private var showsHomeArrivalStatus: Bool {
        switch homeRevealPhase {
        case .waitingForHome, .animating:
            return true
        case .hidden, .waitingForCheckout, .visible:
            return false
        }
    }

    private var hasResolvedInitialHomeLoad: Bool {
        switch viewModel.feedLoadState {
        case .loading:
            return false
        case .loaded, .failed:
            return true
        }
    }

    private var coveringFrostAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    private var needsOnboardingTaste: Bool {
        !hasCompletedTaste && !storeKitManager.hasUnlockedFullApp
    }

    private var hasConfirmedFullAppAccess: Bool {
        storeKitManager.entitlementsReady && storeKitManager.hasUnlockedFullApp
    }

    private var canLoadProfileContent: Bool {
        hasConfirmedFullAppAccess
            && homeRevealPhase == .visible
            && selectedTab == .profile
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
            beginHomeReveal()
            return
        }

        withoutAnimations {
            homeRevealPhase = .hidden
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
                paywallPhase = .locked
            }
            return
        }

        withoutAnimations {
            paywallPhase = .idle
            presentCompose()
        }
    }

    private func beginHomeReveal() {
        switch homeRevealPhase {
        case .waitingForCheckout, .waitingForHome, .animating:
            advanceHomeRevealIfPossible()
            return
        case .visible:
            storeKitManager.releaseCheckoutLock()
            return
        case .hidden:
            break
        }

        hasCompletedTaste = true
        isOnboardingTasteSession = false
        paywallShowsCelebration = false
        paywallHeroCard = nil

        let wasCovered = isComposePresented
            || paywallPhase == .locked

        viewModel.prepareForFullAppAccess()
        withoutAnimations {
            isComposePresented = false
            paywallPhase = .idle
            homeRevealPhase = wasCovered || !hasResolvedInitialHomeLoad
                ? .waitingForCheckout
                : .visible
        }

        if homeRevealPhase == .visible {
            storeKitManager.releaseCheckoutLock()
            return
        }

        storeKitManager.releaseCheckoutLock()
        advanceHomeRevealIfPossible()
    }

    private func advanceHomeRevealIfPossible() {
        guard storeKitManager.entitlementsReady, storeKitManager.hasUnlockedFullApp else {
            return
        }

        switch homeRevealPhase {
        case .waitingForCheckout:
            guard !storeKitManager.isBusy else {
                return
            }
            withoutAnimations {
                homeRevealPhase = .waitingForHome
            }
            advanceHomeRevealIfPossible()
        case .waitingForHome:
            guard hasResolvedInitialHomeLoad else {
                return
            }
            withoutAnimations {
                homeRevealPhase = .animating
            }
            Task { @MainActor in
                await Task.yield()
                guard homeRevealPhase == .animating else {
                    return
                }
                guard storeKitManager.hasUnlockedFullApp else {
                    withoutAnimations {
                        homeRevealPhase = .hidden
                    }
                    return
                }
                guard !storeKitManager.isBusy else {
                    withoutAnimations {
                        homeRevealPhase = .waitingForCheckout
                    }
                    return
                }
                guard hasResolvedInitialHomeLoad else {
                    withoutAnimations {
                        homeRevealPhase = .waitingForHome
                    }
                    return
                }
                withAnimation(coveringFrostAnimation) {
                    homeRevealPhase = .visible
                }
            }
        case .hidden, .animating, .visible:
            return
        }
    }

    private func logOut() {
        storeKitManager.signOut()
        withoutAnimations {
            hasCompletedTaste = false
            paywallShowsCelebration = false
            paywallHeroCard = nil
            paywallPhase = .idle
            viewModel.resetCompose()
            viewModel.resetForSignOut()
            homeRevealPhase = .hidden
            selectedTab = .home
            lastContentTab = .home
            browsePath.removeAll()
            isOnboardingTasteSession = true
            isComposePresented = true
        }
    }

    private func openFollowed(_ person: FollowedPerson) {
        if case .author(let current) = browsePath.last, current.id == person.id {
            return
        }
        browsePath.append(
            .author(
                AuthorRoute(
                    id: person.id,
                    initials: person.initials,
                    avatarPath: person.avatarPath,
                    isSelf: false
                )
            )
        )
    }

    private func openAuthor(_ card: HomeCard) {
        if card.isOwner {
            showOwnProfile()
            return
        }
        guard let authorId = card.authorId else {
            return
        }
        if case .author(let current) = browsePath.last, current.id == authorId {
            return
        }
        browsePath.append(
            .author(
                AuthorRoute(
                    id: authorId,
                    initials: card.authorInitials,
                    avatarPath: card.authorAvatarPath,
                    isSelf: card.isOwner
                )
            )
        )
    }

    private func openModel(_ card: HomeCard) {
        guard let model = card.model else {
            return
        }
        if case .model(let current) = browsePath.last, current.model == model {
            return
        }
        browsePath.append(.model(ModelRoute(model: model)))
    }

    private func showOwnProfile() {
        if !browsePath.isEmpty {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = .profile
            }
            browsePath.removeAll()
            return
        }
        selectedTab = .profile
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
        guard !isOnboardingTasteSession else {
            return
        }

        isOnboardingTasteSession = false
        isComposePresented = false
    }

    private func presentMembershipPaywall() {
        guard isOnboardingTasteSession, storeKitManager.hasEndedMembership else {
            return
        }

        paywallShowsCelebration = false
        paywallHeroCard = nil
        withoutAnimations {
            homeRevealPhase = .hidden
            isComposePresented = false
            isOnboardingTasteSession = false
            paywallPhase = .locked
        }
    }

    private func presentSaveCover(_ label: String) {
        withoutAnimations {
            saveCoverLabel = label
            saveCoverPresented = true
        }
    }

    private func dismissSaveCover(_ cardID: UUID) {
        withoutAnimations {
            isOnboardingTasteSession = false
            isComposePresented = false
        }
        let slide = reduceMotion ? 0.2 : 0.48
        withAnimation(.easeInOut(duration: slide)) {
            saveCoverPresented = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(slide * 1000) + 40))
            guard !saveCoverPresented else {
                return
            }
            saveCoverLabel = nil
            viewModel.highlightSavedCard(cardID)
        }
    }

    private func handleSavedCard(_ card: HomeCard) {
        guard isOnboardingTasteSession else {
            if card.isPublic {
                lastContentTab = .home
                selectedTab = .home
            } else {
                lastContentTab = .profile
                selectedTab = .profile
            }
            return
        }

        lastContentTab = .home
        selectedTab = .home
        paywallHeroCard = card
        paywallShowsCelebration = true
        withoutAnimations {
            homeRevealPhase = .hidden
            paywallPhase = .locked
            isComposePresented = false
            isOnboardingTasteSession = false
        }
        hasCompletedTaste = true
    }

    private func captureHomeInsets(_ insets: EdgeInsets) {
        var next = insets
        if next.bottom > 80 {
            next.bottom = homeSafeAreaInsets.bottom
        }
        homeSafeAreaInsets = next
    }
}

private struct HomeArrivalStatus: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(theme.ink)

            Text("Loading Home.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Home")
    }
}

/// Every card write is optimistic. When one fails the card rolls back on its own, so this
/// is the only thing that says the server was never reached. Sheets that write show their own
/// copy, because this one sits under them.
struct WriteErrorBanner: View {
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
