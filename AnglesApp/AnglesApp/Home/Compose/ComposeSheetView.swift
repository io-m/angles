import SwiftUI

/// Everything the sheet keeps between redraws: AppRoot's handlers, the references its pieces
/// share, its flags, and its running tasks. AppRoot holds one instance. The sheet itself has only
/// plain inputs and this reference, so an AppRoot redraw with the same inputs skips it: a closure
/// among its inputs, or any `@State` of its own, would redraw it every time AppRoot redraws.
@MainActor
final class ComposeSheetContext {
    let edges = ComposeEdges()
    let focus = ComposeFocus()
    let threadFollow = ThreadFollowBox()
    let state = ComposeSheetState()
    /// The save and its cover. A session reset never cancels it: the cover must still slide away.
    var publishTask: Task<Void, Never>?
    /// The reset that follows a close.
    var resetTask: Task<Void, Never>?
    var close: () -> Void = {}
    var showMembership: () -> Void = {}
    var saved: (HomeCard) -> Void = { _ in }
    var landSavedCard: (HomeCard) -> Void = { _ in }
    var presentSaveCover: (String) -> Void = { _ in }
    var dismissSaveCover: (UUID) -> Void = { _ in }
    var acceptTerms: () async -> Bool = { true }
}

/// The sheet's alerts, consent sheet, and save celebration.
@Observable
final class ComposeSheetState {
    var showLeaveAlert = false
    var leavePrompt: ComposeLeavePrompt = .discard
    var isCelebratingSave = false
    var showsAIConsent = false
}

/// Compose: the thread under a header and a bottom bar. This view composes the pieces and routes
/// leaving, consent, and the save. It reads no session state in its body, so a cook, typing, or
/// the keyboard never redraws it.
struct ComposeSheetView: View {
    // Word-sized fields first, the one-byte flags last: a flag in front of a word-sized field
    // leaves padding bytes inside the value, and SwiftUI then never finds two copies equal and
    // redraws the sheet every time AppRoot redraws.
    let session: ComposeSession
    var storeKitManager: StoreKitManager?
    var identityStore: ProfileIdentityStore? = nil
    var context = ComposeSheetContext()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isActive: Bool = true
    var isOnboardingTaste: Bool = false
    var needsTermsAcceptance: Bool = false

    private var edges: ComposeEdges { context.edges }
    private var focus: ComposeFocus { context.focus }
    private var state: ComposeSheetState { context.state }

    var body: some View {
        let _ = RenderCounter.hit("ComposeSheet")
        ComposeThreadView(
            session: session,
            edges: edges,
            focus: focus,
            follow: context.threadFollow,
            identityStore: identityStore,
            isOnboardingTaste: isOnboardingTaste,
            isCelebratingSave: state.isCelebratingSave
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: handleCanvasTap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask { ComposeThreadMask(edges: edges).ignoresSafeArea() }
        .background(alignment: .bottom) {
            // Behind the thread, so it can never tint or cover a line of text.
            ComposeGlow()
                .offset(y: 132)
        }
        .overlay { ComposeWelcome(session: session, isOnboardingTaste: isOnboardingTaste) }
        .safeAreaInset(edge: .top, spacing: 0) {
            ComposeHeader(
                session: session,
                edges: edges,
                isOnboardingTaste: isOnboardingTaste,
                storeKitManager: storeKitManager,
                onClose: requestLeave,
                onShowMembership: {
                    focus.isFocused = false
                    context.showMembership()
                }
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposeBottomBar(
                session: session,
                edges: edges,
                focus: focus,
                isOnboardingTaste: isOnboardingTaste,
                isCelebratingSave: state.isCelebratingSave,
                onSubmit: { submit() },
                onPost: publishAndLeave
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background {
            ComposeSessionEffects(session: session, focus: focus, isActive: isActive)
        }
        .onChange(of: isActive) { _, active in
            if active {
                // Every way in starts a fresh session, so a reset still waiting from the last
                // close would only wipe the new one.
                context.resetTask?.cancel()
                context.resetTask = nil
                state.isCelebratingSave = false
                focus.isFocused = session.phase == .composing
                if isOnboardingTaste {
                    storeKitManager?.clearError()
                }
            } else {
                focus.isFocused = false
                resetAfterDismiss()
            }
        }
        .onDisappear {
            context.publishTask?.cancel()
            context.resetTask?.cancel()
        }
        .alert(state.leavePrompt.title, isPresented: Bindable(state).showLeaveAlert) {
            if state.leavePrompt.allowsLeaving {
                Button(state.leavePrompt.confirmTitle, role: .destructive, action: { context.close() })
                Button(state.leavePrompt.cancelTitle, role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(state.leavePrompt.message)
        }
        .sheet(isPresented: Bindable(state).showsAIConsent) {
            AIConsentSheet(
                onAgree: {
                    guard await context.acceptTerms() else {
                        return false
                    }
                    state.showsAIConsent = false
                    submit(termsJustAccepted: true)
                    return true
                },
                onCancel: {
                    state.showsAIConsent = false
                }
            )
            .interactiveDismissDisabled()
        }
    }

    private func handleCanvasTap() {
        if isOnboardingTaste {
            focus.isFocused = false
            return
        }
        if session.phase == .composing && session.statement.isEmpty {
            requestLeave()
        } else {
            focus.isFocused = false
        }
    }

    private func requestLeave() {
        #if DEBUG
        print("COMPOSE requestLeave phase=\(Self.debugLabel(session.phase)) saving=\(session.isSaving)")
        #endif
        if isOnboardingTaste {
            return
        }
        guard let prompt = ComposeLeavePrompt.resolve(
            isSaving: session.isSaving,
            isBusy: session.isSessionBusy,
            hasWork: session.hasSessionWork
        ) else {
            context.close()
            return
        }
        state.leavePrompt = prompt
        state.showLeaveAlert = true
    }

    private func publishAndLeave() {
        guard !session.isSaving, !state.isCelebratingSave, session.canPublish else {
            return
        }

        context.publishTask = Task {
            guard let savedCard = await session.saveCook(
                forcePrivate: isOnboardingTaste
            ) else {
                return
            }
            if isOnboardingTaste {
                context.saved(savedCard)
                return
            }

            state.isCelebratingSave = true
            let label = savedCard.isPublic ? "Posted" : "Saved privately"
            context.presentSaveCover(label)
            context.landSavedCard(savedCard)
            context.saved(savedCard)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 400 : 1600))
            context.dismissSaveCover(savedCard.id)
        }
    }

    private func resetAfterDismiss() {
        context.resetTask?.cancel()
        context.resetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 250))
            } catch {
                return
            }
            session.resetCompose()
            context.resetTask = nil
        }
    }

    /// `termsJustAccepted` because this view's copy of `needsTermsAcceptance` is the one from
    /// before the agreement landed.
    private func submit(termsJustAccepted: Bool = false) {
        #if DEBUG
        print("COMPOSE submit canSubmit=\(session.canSubmit) phase=\(Self.debugLabel(session.phase)) busy=\(session.isSessionBusy) credits=\(session.hasCreditsForCook)")
        #endif
        guard session.canSubmit else {
            return
        }

        focus.isFocused = false
        if needsTermsAcceptance, !termsJustAccepted {
            state.showsAIConsent = true
            return
        }
        session.sendComposer()
    }

    #if DEBUG
    /// The phase without its payload: a ready cook or an error carries the user's words.
    private static func debugLabel(_ phase: RefinePhase) -> String {
        switch phase {
        case .composing: return "composing"
        case .cooking: return "cooking"
        case .awaitingReply: return "awaitingReply"
        case .ready: return "ready"
        case .error: return "error"
        }
    }
    #endif
}

#Preview {
    ZStack {
        AnglesCanvasBackground()
        ComposeFrost()
        ComposeSheetView(session: HomeViewModel().compose)
    }
}
