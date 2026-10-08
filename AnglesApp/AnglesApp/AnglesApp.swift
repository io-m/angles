import Combine
import SwiftUI
import UserNotifications

private enum HomeRevealPhase: Equatable {
    case hidden
    case waitingForCheckout
    case waitingForHome
    case animating
    case visible
}

private enum SessionEnd {
    case logOut
    case deleted
    case invalidated
}

enum BrowseRoute: Hashable {
    case author(AuthorRoute)
}

@main
struct AnglesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    @State private var sessionStore = SessionStore()
    /// Sparkle compose over Home. The onboarding taste is a destination, not this flag.
    @State private var isComposePresented = false
    @State private var membershipRequested = false
    @State private var selectedTab: RootTab = .home
    @State private var lastContentTab: RootTab = .home
    @State private var browsePath: [BrowseRoute] = []
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var paywallShowsCelebration = false
    @State private var paywallHeroCard: HomeCard?
    @State private var homeRevealPhase: HomeRevealPhase = .hidden
    @State private var splashPhase: LaunchSplashPhase = .holding
    @State private var splashHoldElapsed = false
    @State private var splashMaximumElapsed = false
    @State private var homeFeedTask: Task<Void, Never>?
    @State private var homeArrivalCapTask: Task<Void, Never>?
    @State private var homeArrivalTimedOut = false
    @State private var saveCoverLabel: String?
    @State private var saveCoverPresented = false
    @State private var pendingWidgetDeepLink: AnglesDeepLink?
    @State private var pushCenter = FollowPushCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    private static let homeArrivalCap: Duration = LaunchSplashMotion.maximumHold

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
                        canLoadFullAppContent: isHomeRevealed,
                        isActiveTab: selectedTab == .home,
                        onLogOut: logOut,
                        onOpenAuthor: openAuthor,
                        onInspire: presentCompose
                    )
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(RootTab.home)

                    Color.clear
                        .tabItem { Label("Inspire me", image: "InspireMarkTab") }
                        .tag(RootTab.compose)

                    ProfileView(
                        safeAreaInsets: homeSafeAreaInsets,
                        viewModel: viewModel,
                        storeKitManager: storeKitManager,
                        identityStore: identityStore,
                        onInspire: presentCompose,
                        onLogOut: logOut,
                        onDeleteAccount: deleteAccount,
                        canLoadFullAppContent: canLoadProfileContent,
                        onOpenAuthor: openAuthor,
                        onOpenFollowed: openFollowed
                    )
                    .badge(viewModel.unreadFollowCount)
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
                            onOpenAuthor: openAuthor
                        )
                        .navigationBarBackButtonHidden(true)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tint(theme.ink)
            .opacity(destination == .home ? 1 : 0)
            .allowsHitTesting(isHomeRevealed)
            .accessibilityHidden(!isHomeRevealed)
            .onChange(of: selectedTab) { _, newTab in
                handleTabChange(newTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.keyboard)

            theme.paper
                .ignoresSafeArea()
                .opacity(isHomeCovered ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ComposeFrost()
                .opacity(showsCoveringFrost ? 1 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            ComposeSheetView(
                viewModel: viewModel,
                isActive: isComposeActive,
                isOnboardingTaste: destination == .taste,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onClose: handleComposeClose,
                onShowMembership: presentMembershipPaywall,
                onSave: handleSavedCard,
                onPresentSaveCover: presentSaveCover,
                onDismissSaveCover: dismissSaveCover,
                needsTermsAcceptance: !sessionStore.hasAcceptedTerms,
                onAcceptTerms: { await sessionStore.acceptTerms() }
            )
            .opacity(isComposeActive ? 1 : 0)
            .animation(
                saveCoverPresented
                    ? nil
                    : ComposeMotion.contentFade(reduceMotion, presented: isComposeActive),
                value: isComposeActive
            )
            .allowsHitTesting(isComposeActive)
            .accessibilityHidden(!isComposeActive)

            if let saveCoverLabel {
                GeometryReader { proxy in
                    SaveCelebrationCover(
                        label: saveCoverLabel,
                        playsAnimation: !reduceMotion,
                        safeAreaInsets: homeSafeAreaInsets,
                        size: proxy.size
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(x: saveCoverPresented ? 0 : proxy.size.width)
                }
                .ignoresSafeArea()
                .allowsHitTesting(saveCoverPresented)
                .accessibilityHidden(!saveCoverPresented)
                .zIndex(18)
            }

            WriteErrorBanner(message: viewModel.writeError ?? viewModel.usageBanner ?? serverSyncMessage) {
                if viewModel.writeError != nil {
                    viewModel.dismissWriteError()
                } else if viewModel.usageBanner != nil {
                    viewModel.dismissUsageBanner()
                } else {
                    Task { await storeKitManager.retryServerSync() }
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
                value: viewModel.writeError ?? viewModel.usageBanner ?? serverSyncMessage
            )

            if destination == .paywall {
                PaywallView(
                    storeKitManager: storeKitManager,
                    showsCelebration: paywallShowsCelebration,
                    savedCard: paywallHeroCard,
                    onLogOut: logOut,
                    onDeleteAccount: deleteAccount
                )
                    .transition(.identity)
                    .zIndex(20)
            }

            if destination == .terms {
                AIConsentSheet(
                    cancelTitle: "Log out",
                    onAgree: { await sessionStore.acceptTerms() },
                    onCancel: logOut
                )
                .transition(.opacity)
                .zIndex(22)
            }

            if showsHomeArrivalStatus {
                HomeArrivalStatus()
                    .transition(.opacity)
                    .zIndex(24)
            }

            Group {
                if sessionStore.isSignedIn, storeKitManager.isBusy {
                    CheckoutLockOverlay(lines: storeKitManager.checkoutLockLines)
                        .transition(.opacity)
                }
            }
            .animation(coveringFrostAnimation, value: storeKitManager.isBusy)
            .zIndex(25)

            if destination == .login {
                LoginView(sessionStore: sessionStore) {
                    Task { await sessionStore.retryRestore() }
                }
                .transition(.opacity)
                .zIndex(28)
            }

            if destination == .launching, splashPhase == .finished {
                ColorTokens.paperDark
                    .ignoresSafeArea()
                    .zIndex(30)
                    .accessibilityHidden(true)
            }

            if splashPhase != .finished {
                LaunchSplash(
                    isExiting: splashPhase == .exiting,
                    reduceMotion: reduceMotion,
                    onFinished: completeLaunchSplash
                )
                .zIndex(40)
                .allowsHitTesting(true)
            }
        }
        .environment(\.profileIdentity, identityStore)
        .onReceive(
            NotificationCenter.default.publisher(for: .anglesSessionInvalidated)
                .receive(on: DispatchQueue.main)
        ) { note in
            guard sessionStore.isInvalidation(of: note.object as? String) else {
                return
            }
            endSession(.invalidated)
        }
        .task {
            identityStore.onSynced = { initials, avatarPath in
                viewModel.applyOwnerIdentity(initials: initials, avatarPath: avatarPath)
            }
        }
        .task {
            await launch()
        }
        .task {
            try? await Task.sleep(for: LaunchSplashMotion.minimumHold)
            guard splashPhase == .holding else {
                return
            }
            splashHoldElapsed = true
            tryFinishLaunchSplashIfReady()
            advanceHomeRevealIfPossible()
        }
        .task {
            try? await Task.sleep(for: LaunchSplashMotion.maximumHold)
            guard splashPhase == .holding else {
                return
            }
            splashMaximumElapsed = true
            tryFinishLaunchSplashIfReady()
            advanceHomeRevealIfPossible()
        }
        .task(id: sessionStore.session?.id) {
            viewModel.configureUsageAccount(userID: sessionStore.session?.id)
            guard sessionStore.isSignedIn, splashPhase == .finished else {
                return
            }
            await loadDeferredSignedInWork()
        }
        .onChange(of: splashPhase) { _, phase in
            guard phase == .finished, sessionStore.isSignedIn else {
                return
            }
            Task { await loadDeferredSignedInWork() }
        }
        .onChange(of: destination) { old, new in
            handleDestinationChange(from: old, to: new)
        }
        .onChange(of: viewModel.tasteEndedByServer) { _, ended in
            guard ended, destination == .taste else {
                return
            }
            withoutAnimations {
                paywallShowsCelebration = false
                paywallHeroCard = nil
                membershipRequested = true
            }
        }
        .onOpenURL { url in
            handleWidgetURL(url)
        }
        .onChange(of: sessionStore.session?.id) { _, _ in
            if let session = sessionStore.session {
                storeKitManager.configureAccount(userID: session.id)
                viewModel.configureUsageAccount(userID: session.id)
                identityStore.applySession(session)
            } else {
                storeKitManager.configureAccount(userID: nil)
                viewModel.configureUsageAccount(userID: nil)
                viewModel.resetForSignOut()
                identityStore.reset()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, sessionStore.isSignedIn {
                Task { await syncFollowPush() }
            }
            // A subscription can lapse while the app is alive. Ask Apple again on every
            // foreground so Home cannot outlive the entitlement until the next cold launch.
            guard phase == .active,
                  sessionStore.isSignedIn,
                  storeKitManager.entitlementsReady,
                  !storeKitManager.isBusy else {
                return
            }
            Task {
                await storeKitManager.refreshEntitlements()
                await storeKitManager.probeSubscriptionOffer()
                await viewModel.loadFollowNotifications()
                syncAppBadge()
            }
        }
        .onChange(of: pushCenter.tokenRevision) { _, _ in
            guard let token = pushCenter.deviceToken, sessionStore.isSignedIn else {
                return
            }
            Task { await registerPushToken(token) }
        }
        .onChange(of: pushCenter.pendingActorID) { _, actorId in
            guard actorId != nil else {
                return
            }
            consumeFollowPush()
        }
        .onChange(of: viewModel.followBadgeRevision) { _, _ in
            syncAppBadge()
        }
        .onChange(of: storeKitManager.isBusy) { _, _ in
            handleCheckoutStateChange()
        }
        .onChange(of: storeKitManager.isCheckoutOperationInFlight) { _, _ in
            handleCheckoutStateChange()
        }
        .onChange(of: viewModel.feedLoadState) { _, _ in
            advanceHomeRevealIfPossible()
        }
        .onChange(of: viewModel.launchPrefetchFinished) { _, _ in
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

    // MARK: - Gate

    /// Read in one pass from the stores, so a destination never mixes a cleared value with a
    /// stale one.
    private var gateInputs: AppGateInputs {
        AppGateInputs(
            sessionRestored: sessionStore.isRestored,
            entitlementsReady: storeKitManager.entitlementsReady,
            isSignedIn: sessionStore.isSignedIn,
            isEntitled: storeKitManager.isEntitledForGate,
            serverTasteCompleted: sessionStore.hasCompletedTaste,
            membershipRequested: membershipRequested,
            termsAccepted: sessionStore.hasAcceptedTerms
        )
    }

    private var destination: AppDestination {
        AppGate.resolve(gateInputs)
    }

    /// The first frame of a Home destination is covered even before the reveal starts.
    private var isHomeCovered: Bool {
        destination == .home && homeRevealPhase != .visible
    }

    private var isHomeRevealed: Bool {
        destination == .home && homeRevealPhase == .visible
    }

    private var isComposeActive: Bool {
        destination == .taste || (destination == .home && isComposePresented)
    }

    private var showsCoveringFrost: Bool {
        isComposeActive || isHomeCovered || destination == .paywall
    }

    private var showsHomeArrivalStatus: Bool {
        guard splashPhase == .finished, destination == .home else {
            return false
        }
        switch homeRevealPhase {
        case .waitingForHome, .animating:
            return true
        case .hidden, .waitingForCheckout, .visible:
            return false
        }
    }

    private var hasResolvedInitialHomeLoad: Bool {
        if homeArrivalTimedOut || splashMaximumElapsed {
            return true
        }
        return viewModel.launchPrefetchFinished
    }

    private var coveringFrostAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    private var canLoadProfileContent: Bool {
        isHomeRevealed && selectedTab == .profile
    }

    private var serverSyncMessage: String? {
        storeKitManager.serverSyncPending ? storeKitManager.errorMessage : nil
    }

    private func withoutAnimations(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    private func launch() async {
        removeLegacyTasteFlags()
        let store = storeKitManager
        sessionStore.prepareAccountAccess = { session in
            store.configureAccount(userID: session.id)
            await store.resumeAfterAccountSignIn()
        }
        async let sessionRestore: Void = sessionStore.restore()
        async let productLoad: Void = storeKitManager.loadProducts()
        _ = await (sessionRestore, productLoad)
        if let session = sessionStore.session {
            Task { await viewModel.prefetchLaunchFeed(userId: session.id) }
        }
        storeKitManager.configureAccount(userID: sessionStore.session?.id)
        viewModel.configureUsageAccount(userID: sessionStore.session?.id)
        await storeKitManager.prepare(hasAccountSession: sessionStore.isSignedIn)
    }

    private func loadDeferredSignedInWork() async {
        await viewModel.loadUsageIfNeeded()
        await viewModel.loadFollowNotifications()
        consumeFollowPush()
        await syncFollowPush()
    }

    /// The server's consumed/completed timestamps are the only taste flags since Auth.
    private func removeLegacyTasteFlags() {
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboardingTaste")
        UserDefaults.standard.removeObject(forKey: "hasEnteredPaywallFlow")
    }

    private func handleDestinationChange(from old: AppDestination, to new: AppDestination) {
        #if DEBUG
        print("[Angles Gate] \(old) -> \(new) \(gateInputs) storekit: \(storeKitManager.debugSnapshot)")
        #endif
        if old == .home, new != .home {
            leaveHome()
        }
        if new == .home, old != .home {
            enterHome()
        }
        if new == .terms {
            releaseCheckoutLockForTerms()
        }
        if new == .taste, old != .taste {
            viewModel.resetCompose()
            viewModel.composeIsPublic = false
            storeKitManager.clearError()
        }
        if new != .paywall {
            paywallShowsCelebration = false
            paywallHeroCard = nil
        }
        if new == .home {
            membershipRequested = false
            consumeFollowPush()
        }
        tryFinishLaunchSplashIfReady()
    }

    /// Home is already covered on this frame. Taste/paywall are gone structurally; the reveal
    /// waits for checkout, then the first Home result, then fades once.
    private func enterHome() {
        viewModel.prepareForFullAppAccess()
        withoutAnimations {
            isComposePresented = false
            homeArrivalTimedOut = false
            homeRevealPhase = .waitingForCheckout
            selectedTab = .home
            lastContentTab = .home
            browsePath.removeAll()
        }
        homeFeedTask?.cancel()
        homeFeedTask = Task { await viewModel.loadFeedIfNeeded() }
        storeKitManager.releaseCheckoutLock()
        advanceHomeRevealIfPossible()
    }

    private func leaveHome() {
        homeFeedTask?.cancel()
        homeFeedTask = nil
        homeArrivalCapTask?.cancel()
        homeArrivalCapTask = nil
        withoutAnimations {
            homeRevealPhase = .hidden
            homeArrivalTimedOut = false
            isComposePresented = false
        }
    }

    private func handleCheckoutStateChange() {
        // A Restore from Settings while Home is already showing has nothing left to reveal.
        if isHomeRevealed, !storeKitManager.isCheckoutOperationInFlight {
            storeKitManager.releaseCheckoutLock()
        }
        if destination == .terms {
            releaseCheckoutLockForTerms()
        }
        advanceHomeRevealIfPossible()
    }

    /// A purchase holds the lock until Home, but an account without Terms stops at the Terms
    /// screen first, which sits under the lock.
    private func releaseCheckoutLockForTerms() {
        guard !storeKitManager.isCheckoutOperationInFlight else {
            return
        }
        storeKitManager.releaseCheckoutLock()
    }

    private func advanceHomeRevealIfPossible() {
        guard destination == .home else {
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
            startHomeArrivalCap()
            advanceHomeRevealIfPossible()
        case .waitingForHome:
            guard hasResolvedInitialHomeLoad else {
                return
            }
            if splashPhase == .holding {
                guard splashHoldElapsed else {
                    return
                }
                homeArrivalCapTask?.cancel()
                homeArrivalCapTask = nil
                withoutAnimations {
                    homeRevealPhase = .visible
                }
                beginLaunchSplashExit()
                applyPendingWidgetDeepLinkIfPossible()
                consumeFollowPush()
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
                guard destination == .home else {
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
                homeArrivalCapTask?.cancel()
                homeArrivalCapTask = nil
                withAnimation(coveringFrostAnimation) {
                    homeRevealPhase = .visible
                }
                applyPendingWidgetDeepLinkIfPossible()
                consumeFollowPush()
            }
        case .hidden, .animating, .visible:
            return
        }
    }

    /// Login, taste, paywall, and Terms leave as soon as the gate is ready and the splash has
    /// had its minimum hold. Home waits for the first feed result in `advanceHomeRevealIfPossible`.
    private func tryFinishLaunchSplashIfReady() {
        guard splashPhase == .holding, splashHoldElapsed else {
            return
        }
        switch destination {
        case .launching, .home:
            return
        case .login, .taste, .paywall, .terms:
            beginLaunchSplashExit()
        }
    }

    private func beginLaunchSplashExit() {
        guard splashPhase == .holding else {
            return
        }
        splashPhase = .exiting
    }

    private func completeLaunchSplash() {
        withoutAnimations {
            splashPhase = .finished
        }
    }

    /// Loading Home is bounded. Past the cap Home appears with its own loading or Retry state.
    private func startHomeArrivalCap() {
        homeArrivalCapTask?.cancel()
        homeArrivalCapTask = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.homeArrivalCap)
            } catch {
                return
            }
            guard destination == .home, homeRevealPhase == .waitingForHome else {
                return
            }
            homeArrivalTimedOut = true
            advanceHomeRevealIfPossible()
        }
    }

    // MARK: - Session

    private func registerPushToken(_ token: String) async {
        do {
            try await ProfileService().registerDevice(token: token, environment: FollowPush.tokenEnvironment)
            #if DEBUG
            print("[Angles Push] registered \(FollowPush.tokenEnvironment) token")
            #endif
        } catch {
            // The next foreground registers again.
            #if DEBUG
            print("[Angles Push] token registration with the API failed: \(error)")
            #endif
        }
    }

    /// iOS permission is the only off switch. If this phone can show banners, keep a token
    /// and heal a leftover account flag from the old in-app toggle.
    private func syncFollowPush() async {
        await FollowPush.reconcile(notifyFollows: true)
        let status = await FollowPush.authorizationStatus()
        if FollowPush.isAllowed(status), sessionStore.session?.notifyFollows == false {
            _ = await sessionStore.setNotifyFollows(true)
        }
        if let token = pushCenter.deviceToken, FollowPush.isAllowed(status) {
            await registerPushToken(token)
        }
    }

    /// The icon number is the unread count, set every time it is read so a stale number from
    /// a push cannot outlive it.
    private func syncAppBadge() {
        let count = sessionStore.isSignedIn ? viewModel.unreadFollowCount : 0
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    /// Lock-screen tap or action. View profile opens their posts; Follow back opens the bell
    /// and follows. Pending state waits until Home is revealed — the same gate as widget links —
    /// so enterHome cannot wipe the author page and the cover cannot hide it.
    private func consumeFollowPush() {
        guard sessionStore.isSignedIn,
              isHomeRevealed,
              let actorId = pushCenter.pendingActorID,
              let id = FollowPush.uuid(from: actorId)
        else {
            return
        }
        let intent = pushCenter.pendingIntent
        pushCenter.clearPending()
        switch intent {
        case .viewProfile:
            openAuthorFromFollowPush(id)
        case .followBack:
            selectedTab = .profile
            lastContentTab = .profile
            viewModel.requestOpenFollowNotifications()
            viewModel.followBack(id)
        }
    }

    private func openAuthorFromFollowPush(_ authorId: UUID) {
        // Author pages sit on the NavigationStack that wraps the tabs. Do not change
        // selectedTab here: switching Home after a push pops that stack and lands on Home.
        if let notice = viewModel.followNotices.first(where: { $0.actorId == authorId }) {
            openFollowed(
                FollowedPerson(
                    id: notice.actorId,
                    initials: notice.initials,
                    avatarPath: notice.avatarPath
                )
            )
        } else {
            openFollowed(FollowedPerson(id: authorId, initials: "", avatarPath: nil))
        }
    }

    private func logOut() {
        endSession(.logOut)
    }

    private func deleteAccount() async -> AccountDeletion {
        let result = await sessionStore.deleteAccount()
        if result == .deleted {
            endSession(.deleted)
        }
        return result
    }

    /// Logout, account deletion, and a rejected session all end here. Nothing awaits before the
    /// session clears, so the next frame is Login — never taste, paywall, or Home.
    private func endSession(_ reason: SessionEnd) {
        if reason == .logOut {
            let deviceToken = UserDefaults.standard.string(forKey: FollowPush.tokenDefaultsKey)
            let bearer = AuthCredentials.shared.bearerToken
            if let deviceToken, let bearer, !bearer.isEmpty {
                Task {
                    try? await ProfileService().unregisterDevice(token: deviceToken, bearer: bearer)
                }
            }
        }
        homeFeedTask?.cancel()
        homeFeedTask = nil
        homeArrivalCapTask?.cancel()
        homeArrivalCapTask = nil
        withoutAnimations {
            sessionStore.endLocalSession(revokeOnServer: reason == .logOut)
            storeKitManager.signOut()
            viewModel.configureUsageAccount(userID: nil)
            membershipRequested = false
            paywallShowsCelebration = false
            paywallHeroCard = nil
            isComposePresented = false
            homeRevealPhase = .hidden
            homeArrivalTimedOut = false
            saveCoverLabel = nil
            saveCoverPresented = false
            viewModel.resetCompose()
            viewModel.resetForSignOut()
            identityStore.reset()
        }
    }

    // MARK: - Navigation

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

    // MARK: - Compose

    private func handleWidgetURL(_ url: URL) {
        guard let deepLink = AnglesDeepLink(url: url) else {
            return
        }
        pendingWidgetDeepLink = deepLink
        applyPendingWidgetDeepLinkIfPossible()
    }

    private func applyPendingWidgetDeepLinkIfPossible() {
        guard isHomeRevealed, let deepLink = pendingWidgetDeepLink else {
            return
        }
        pendingWidgetDeepLink = nil

        switch deepLink {
        case .favorites:
            withoutAnimations {
                isComposePresented = false
                browsePath.removeAll()
                viewModel.profileGridFilter = .favorites
                selectedTab = .profile
                lastContentTab = .profile
            }
        case .compose:
            presentCompose()
        }
    }

    private func presentCompose() {
        guard destination == .home, !isComposePresented else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.resetCompose()
        isComposePresented = true
    }

    private func handleComposeClose() {
        guard destination != .taste else {
            return
        }
        isComposePresented = false
    }

    private func presentMembershipPaywall() {
        guard destination == .taste, storeKitManager.hasEndedMembership else {
            return
        }

        withoutAnimations {
            paywallShowsCelebration = false
            paywallHeroCard = nil
            membershipRequested = true
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
            isComposePresented = false
        }
        slideSaveCoverAway {
            viewModel.highlightSavedCard(cardID)
        }
    }

    /// The ride is already moving, so the cover leaves with speed instead of easing in from a stop.
    private func slideSaveCoverAway(_ completion: @escaping () -> Void) {
        let slide = reduceMotion ? 0.2 : 0.38
        withAnimation(.easeOut(duration: slide)) {
            saveCoverPresented = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(slide * 1000) + 40))
            guard !saveCoverPresented else {
                return
            }
            saveCoverLabel = nil
            completion()
        }
    }

    /// The server stamped `tasteCompletedAt` in the same transaction as the card. Recording it
    /// locally moves the destination to the celebrating paywall in this frame.
    private func handleSavedCard(_ card: HomeCard) {
        guard destination == .taste else {
            if card.isPublic {
                lastContentTab = .home
                selectedTab = .home
            } else {
                lastContentTab = .profile
                selectedTab = .profile
            }
            return
        }

        withoutAnimations {
            lastContentTab = .home
            selectedTab = .home
            paywallHeroCard = card
            paywallShowsCelebration = true
            sessionStore.noteTasteCompleted()
        }
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
                .accessibilityHint("Dismisses the message or retries the failed sync")
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard)
    }
}
