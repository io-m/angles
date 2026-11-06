import Combine
import StoreKit
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

@main
struct AnglesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .preferredColorScheme(.dark)
                .modifier(UserAppearance(store: themeStore))
                .task { FrameMonitor.start() }
        }
    }
}

struct AppRoot: View {
    @State private var viewModel = HomeViewModel()
    @State private var storeKitManager = StoreKitManager()
    @State private var reviewCoordinator = AppStoreReviewCoordinator()
    @State private var identityStore = ProfileIdentityStore()
    @State private var sessionStore = SessionStore()
    /// Sparkle compose over Home. The onboarding taste is a destination, not this flag.
    @State private var isComposePresented = false
    @State private var membershipRequested = false
    @State private var stackScreenState = StackScreenState()
    @State private var showsProfile = false
    @State private var authorRoute: AuthorRoute?
    @State private var postRoute: PostRoute?
    /// The other sheet waits until the one on screen has closed.
    @State private var profileAfterAuthor = false
    @State private var authorAfterProfile: AuthorRoute?
    @State private var postAfterSheet: PostRoute?
    @State private var notificationsAfterSheet = false
    @State private var isRegisteringPushToken = false
    /// Profile's own author sheet. A rating prompt treats that as away from Home.
    @State private var profileCoversWithAuthor = false
    @State private var homeSafeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    @State private var paywallShowsCelebration = false
    @State private var paywallHeroCard: HomeCard?
    @State private var homeRevealPhase: HomeRevealPhase = .hidden
    @State private var splashPhase: LaunchSplashPhase = .holding
    @State private var splashHoldElapsed = false
    @State private var splashMaximumElapsed = false
    @State private var homeArrivalCapTask: Task<Void, Never>?
    @State private var homeArrivalTimedOut = false
    @State private var saveCoverLabel: String?
    @State private var saveCoverPresented = false
    @State private var pendingWidgetDeepLink: AnglesDeepLink?
    @State private var pushCenter = FollowPushCenter.shared
    @State private var composeContext = ComposeSheetContext()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var themeStore: ThemeStore

    private static let homeArrivalCap: Duration = LaunchSplashMotion.maximumHold

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let _ = RenderCounter.hit("AppRoot")
        ZStack {
            theme.paper
                .ignoresSafeArea()

            StackHome(
                viewModel: viewModel,
                safeAreaInsets: homeSafeAreaInsets,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                screenState: stackScreenState,
                onLogOut: logOut,
                onDeleteAccount: deleteAccount,
                onInspire: presentCompose,
                onOpenProfile: showOwnProfile,
                onOpenAuthor: openAuthor,
                onOpenFollowed: openFollowed,
                onOpenPost: showPost,
                onSheetDismissed: presentQueuedBrowseSheet,
                isHomeActive: isHomeInteractive
            )
            .sheet(isPresented: $showsProfile, onDismiss: {
                profileCoversWithAuthor = false
                presentQueuedBrowseSheet()
            }) {
                profileSheet
            }
            .sheet(item: $authorRoute, onDismiss: presentQueuedBrowseSheet) { route in
                authorSheet(route)
            }
            .sheet(item: $postRoute, onDismiss: presentQueuedBrowseSheet) { route in
                postSheet(route)
            }
            .tint(theme.ink)
            .opacity(destination == .home ? 1 : 0)
            .allowsHitTesting(isHomeRevealed)
            .accessibilityHidden(!isHomeRevealed)
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
                session: viewModel.compose,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                context: composeContext,
                isActive: isComposeActive,
                isOnboardingTaste: destination == .taste,
                needsTermsAcceptance: !sessionStore.hasAcceptedTerms
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

            RootMessageBanner(viewModel: viewModel, storeKitManager: storeKitManager)

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
        .environment(sessionStore)
        .onChange(of: sessionStore.session?.id, initial: true) { _, _ in syncLoveDisclosure() }
        .onChange(of: sessionStore.session?.shareLoveName) { _, _ in syncLoveDisclosure() }
        .onAppear(perform: configureComposeContext)
        .task(id: reviewCoordinator.promptGeneration) {
            guard reviewCoordinator.promptGeneration > 0 else {
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            reviewCoordinator.considerPrompt(
                context: settledSaveReviewContext,
                storeEnvironment: storeKitManager.storeEnvironment
            ) {
                requestReview()
                return true
            }
        }
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
            Task { await askFollowPushOnHomeIfNeeded() }
        }
        .onChange(of: homeRevealPhase) { _, phase in
            guard phase == .visible else {
                return
            }
            Task { await askFollowPushOnHomeIfNeeded() }
        }
        .onChange(of: destination) { old, new in
            handleDestinationChange(from: old, to: new)
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
            if phase == .background {
                viewModel.stack.noteBackground()
            }
            if phase == .active, isHomeRevealed {
                viewModel.stack.noteForeground()
            }
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
        .onChange(of: storeKitManager.isBusy) { _, _ in
            handleCheckoutStateChange()
        }
        .background {
            RootChangeObservers(
                viewModel: viewModel,
                storeKitManager: storeKitManager,
                pushCenter: pushCenter,
                onHomeLoadProgress: advanceHomeRevealIfPossible,
                onTasteEnded: handleTasteEndedByServer,
                onFollowBadgeChange: syncAppBadge,
                onPushTokenChange: handlePushTokenChange,
                onIncomingNotification: handleIncomingNotification,
                onPushActor: consumeFollowPush,
                onCheckoutOperationChange: handleCheckoutStateChange
            )
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

    private var isHomeInteractive: Bool {
        isHomeRevealed
            && !isComposePresented
            && !saveCoverPresented
            && !showsProfile
            && authorRoute == nil
            && postRoute == nil
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
        return viewModel.stack.firstLoadFinished
    }

    private var coveringFrostAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.45)
    }

    /// Set once: the handlers act on this view's live state, so they never go stale.
    private func configureComposeContext() {
        composeContext.close = handleComposeClose
        composeContext.showMembership = presentMembershipPaywall
        composeContext.saved = handleSavedCard
        composeContext.presentSaveCover = presentSaveCover
        composeContext.dismissSaveCover = dismissSaveCover
        composeContext.acceptTerms = { await sessionStore.acceptTerms() }
    }

    private func handleTasteEndedByServer() {
        guard destination == .taste else {
            return
        }
        withoutAnimations {
            paywallShowsCelebration = false
            paywallHeroCard = nil
            membershipRequested = true
        }
    }

    private func handlePushTokenChange() {
        guard let token = pushCenter.deviceToken, sessionStore.isSignedIn else {
            return
        }
        Task { await registerPushToken(token) }
    }

    private func handleIncomingNotification() {
        guard sessionStore.isSignedIn else {
            return
        }
        Task {
            await viewModel.loadFollowNotifications()
            syncAppBadge()
        }
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
        if sessionStore.session != nil {
            viewModel.stack.startVisitIfNeeded()
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
            viewModel.compose.resetCompose()
            viewModel.compose.composeIsPublic = false
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
        withoutAnimations {
            isComposePresented = false
            homeArrivalTimedOut = false
            homeRevealPhase = .waitingForCheckout
            dismissBrowseSheets()
        }
        // A launch prefetch that failed before the entitlement settled gets one more try here.
        if viewModel.stack.loadState == .failed, viewModel.stack.deck.cards.isEmpty {
            viewModel.stack.retry()
        } else {
            viewModel.stack.startVisitIfNeeded()
        }
        storeKitManager.releaseCheckoutLock()
        advanceHomeRevealIfPossible()
    }

    private func leaveHome() {
        homeArrivalCapTask?.cancel()
        homeArrivalCapTask = nil
        withoutAnimations {
            homeRevealPhase = .hidden
            homeArrivalTimedOut = false
            dismissBrowseSheets()
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
        guard !isRegisteringPushToken else {
            return
        }
        isRegisteringPushToken = true
        defer { isRegisteringPushToken = false }
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
    /// and heal a leftover account flag from the old in-app toggle. Does not show the OS dialog.
    private func syncFollowPush() async {
        await FollowPush.reconcile(notifyFollows: true)
        let status = await FollowPush.authorizationStatus()
        if FollowPush.isAllowed(status), sessionStore.session?.notifyFollows == false {
            _ = await sessionStore.setNotifyFollows(true)
        }
    }

    /// iOS's dialog only after Home is up and splash is gone — never over login, taste, or paywall.
    private func askFollowPushOnHomeIfNeeded() async {
        guard sessionStore.isSignedIn, isHomeRevealed, splashPhase == .finished else {
            return
        }
        await FollowPush.askOnceOnHome()
    }

    /// The icon number is the unread count, set every time it is read so a stale number from
    /// a push cannot outlive it.
    private func syncAppBadge() {
        let count = sessionStore.isSignedIn ? viewModel.unreadNotificationCount : 0
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    /// Lock-screen tap or action. View profile opens their posts; Follow back opens People
    /// and follows. Pending state waits until Home is revealed — the same gate as widget links —
    /// so enterHome cannot wipe the author page and the cover cannot hide it.
    private func syncLoveDisclosure() {
        viewModel.loveDisclosure = (sessionStore.session?.id, sessionStore.session?.shareLoveName ?? true)
    }

    private func consumeFollowPush() {
        guard sessionStore.isSignedIn, isHomeRevealed else {
            return
        }
        if let lovePush = pushCenter.pendingLovePush {
            pushCenter.clearPending()
            isComposePresented = false
            viewModel.markPushNotificationRead(
                loveId: lovePush.notificationId,
                cardId: lovePush.cardId
            )
            if let cardId = lovePush.cardId {
                showPost(PostRoute(id: cardId, initialStyle: lovePush.style))
            } else {
                showNotifications()
            }
            return
        }
        guard let actorId = pushCenter.pendingActorID,
              let id = FollowPush.uuid(from: actorId)
        else {
            return
        }
        let followNotificationId = pushCenter.pendingFollowNotificationID
        let intent = pushCenter.pendingIntent
        pushCenter.clearPending()
        isComposePresented = false
        viewModel.markPushNotificationRead(followId: followNotificationId)
        switch intent {
        case .viewProfile:
            openAuthorFromFollowPush(id)
        case .followBack:
            showNotifications()
            viewModel.followBack(id)
        }
    }

    private func openAuthorFromFollowPush(_ authorId: UUID) {
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
            viewModel.compose.resetCompose()
            viewModel.resetForSignOut()
            identityStore.reset()
            dismissBrowseSheets()
        }
    }

    // MARK: - Navigation

    private var profileSheet: some View {
        ProfileView(
            viewModel: viewModel,
            storeKitManager: storeKitManager,
            identityStore: identityStore,
            onInspire: presentCompose,
            onLogOut: logOut,
            onDeleteAccount: deleteAccount,
            canLoadFullAppContent: isHomeRevealed,
            onAuthorVisibility: { profileCoversWithAuthor = $0 }
        )
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .modifier(UserAppearance(store: themeStore))
    }

    private func authorSheet(_ route: AuthorRoute) -> some View {
        AuthorProfileView(route: route, viewModel: viewModel)
            .presentationDetents([.large])
            .presentationContentInteraction(.scrolls)
            .modifier(UserAppearance(store: themeStore))
    }

    private func postSheet(_ route: PostRoute) -> some View {
        PostDetailView(
            route: route,
            viewModel: viewModel,
            onClose: {
                postRoute = nil
            },
            onOpenLover: { person in
                openFollowed(person)
            }
        )
        .id(route.id)
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .modifier(UserAppearance(store: themeStore))
    }

    private func openFollowed(_ person: FollowedPerson) {
        showAuthor(
            AuthorRoute(
                id: person.id,
                initials: person.initials,
                avatarPath: person.avatarPath,
                isSelf: false
            )
        )
    }

    /// One sheet at a time over Home. Any open sheet closes first, then the requested one opens.
    private func showPost(_ route: PostRoute) {
        if postRoute != nil, !showsProfile, authorRoute == nil, !stackScreenState.hasPresentedSheet {
            postRoute = route
            return
        }
        if showsProfile || authorRoute != nil || stackScreenState.hasPresentedSheet {
            postAfterSheet = route
            authorAfterProfile = nil
            profileAfterAuthor = false
            notificationsAfterSheet = false
            showsProfile = false
            authorRoute = nil
            stackScreenState.dismissSheets()
            return
        }
        postRoute = route
    }

    private func showAuthor(_ route: AuthorRoute) {
        if authorRoute?.id == route.id, !showsProfile, postRoute == nil, !stackScreenState.hasPresentedSheet {
            return
        }
        if showsProfile || postRoute != nil || stackScreenState.hasPresentedSheet {
            authorAfterProfile = route
            postAfterSheet = nil
            profileAfterAuthor = false
            notificationsAfterSheet = false
            showsProfile = false
            postRoute = nil
            stackScreenState.dismissSheets()
            return
        }
        authorRoute = route
    }

    private func openAuthor(_ card: HomeCard) {
        if card.isOwner {
            showOwnProfile()
            return
        }
        guard let authorId = card.authorId else {
            return
        }
        showAuthor(
            AuthorRoute(
                id: authorId,
                initials: card.authorInitials,
                avatarPath: card.authorAvatarPath,
                isSelf: false
            )
        )
    }

    /// Your profile, as a sheet. Any other sheet closes first, then this one opens.
    private func showOwnProfile() {
        if authorRoute != nil || postRoute != nil || stackScreenState.hasPresentedSheet {
            profileAfterAuthor = true
            authorAfterProfile = nil
            postAfterSheet = nil
            notificationsAfterSheet = false
            authorRoute = nil
            postRoute = nil
            stackScreenState.dismissSheets()
            return
        }
        showsProfile = true
    }

    private func showNotifications() {
        if stackScreenState.showPeople {
            stackScreenState.peopleStartsOnNotifications = true
            return
        }
        if showsProfile || authorRoute != nil || postRoute != nil || stackScreenState.showFilter || stackScreenState.showSettings {
            notificationsAfterSheet = true
            postAfterSheet = nil
            authorAfterProfile = nil
            profileAfterAuthor = false
            showsProfile = false
            authorRoute = nil
            postRoute = nil
            stackScreenState.dismissSheets()
            return
        }
        stackScreenState.openNotifications()
    }

    private func presentQueuedBrowseSheet() {
        if let route = postAfterSheet {
            postAfterSheet = nil
            postRoute = route
            return
        }
        if let route = authorAfterProfile {
            authorAfterProfile = nil
            authorRoute = route
            return
        }
        if profileAfterAuthor {
            profileAfterAuthor = false
            showsProfile = true
            return
        }
        if notificationsAfterSheet {
            notificationsAfterSheet = false
            stackScreenState.openNotifications()
        }
    }

    private func dismissBrowseSheets() {
        showsProfile = false
        authorRoute = nil
        postRoute = nil
        profileAfterAuthor = false
        authorAfterProfile = nil
        postAfterSheet = nil
        notificationsAfterSheet = false
        profileCoversWithAuthor = false
        stackScreenState.dismissSheets()
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
        case .saved:
            withoutAnimations {
                isComposePresented = false
                viewModel.profileSegment = .saved
                authorRoute = nil
                postRoute = nil
                stackScreenState.dismissSheets()
                showsProfile = true
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
        viewModel.compose.resetCompose()
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
            viewModel.announcePost(cardID)
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
            reviewCoordinator.schedulePrompt()
        }
    }

    /// Read after the save cover has left. A covered or off-home screen never asks.
    private var settledSaveReviewContext: AppRatingPromptContext {
        let onRootList = authorRoute == nil && postRoute == nil && !profileCoversWithAuthor
        return AppRatingPromptContext(
            destinationIsHome: destination == .home,
            homeIsRevealed: isHomeRevealed,
            composeVisible: isComposePresented,
            saveCoverVisible: saveCoverPresented || saveCoverLabel != nil,
            onHomeOrProfile: onRootList,
            sceneIsActive: scenePhase == .active
        )
    }

    /// The server stamped `tasteCompletedAt` in the same transaction as the card. Recording it
    /// locally moves the destination to the celebrating paywall in this frame.
    private func handleSavedCard(_ card: HomeCard) {
        guard destination == .taste else {
            reviewCoordinator.noteSuccessfulEntitledSave(
                isEntitled: storeKitManager.isEntitledForGate,
                safetyClear: !viewModel.compose.composeSessionNeedsCare
            )
            return
        }

        withoutAnimations {
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

/// AppRoot's reactions to values it never draws. They live here so a stack page landing, a badge
/// count, or a push token redraws this empty view, not the root and everything under it.
private struct RootChangeObservers: View {
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    let pushCenter: FollowPushCenter
    var onHomeLoadProgress: () -> Void
    var onTasteEnded: () -> Void
    var onFollowBadgeChange: () -> Void
    var onPushTokenChange: () -> Void
    var onIncomingNotification: () -> Void
    var onPushActor: () -> Void
    var onCheckoutOperationChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: viewModel.tasteEndedByServer) { _, ended in
                if ended {
                    onTasteEnded()
                }
            }
            .onChange(of: pushCenter.tokenRevision) { _, _ in
                onPushTokenChange()
            }
            .onChange(of: pushCenter.incomingNotificationRevision) { _, _ in
                onIncomingNotification()
            }
            .onChange(of: pushCenter.pendingActorID) { _, actorId in
                if actorId != nil {
                    onPushActor()
                }
            }
            .onChange(of: pushCenter.pendingLovePush) { _, pending in
                if pending != nil {
                    onPushActor()
                }
            }
            .onChange(of: viewModel.followBadgeRevision) { _, _ in
                onFollowBadgeChange()
            }
            .onChange(of: storeKitManager.isCheckoutOperationInFlight) { _, _ in
                onCheckoutOperationChange()
            }
            .onChange(of: viewModel.stack.firstLoadFinished) { _, _ in
                onHomeLoadProgress()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The root banner. It reads its messages itself, so a failed save or a credit warning redraws
/// only the banner.
private struct RootMessageBanner: View {
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let message = viewModel.writeError
            ?? viewModel.usageBanner
            ?? (storeKitManager.serverSyncPending ? storeKitManager.errorMessage : nil)
        WriteErrorBanner(message: message) {
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
            value: message
        )
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
