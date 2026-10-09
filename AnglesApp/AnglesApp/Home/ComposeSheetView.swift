import Lottie
import SwiftUI

struct ComposeFrost: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)

            theme.surface
                .opacity(colorScheme == .dark ? 0.14 : 0.10)
        }
        .accessibilityHidden(true)
    }
}

enum ComposeMotion {
    static func fade(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.12) : .linear(duration: 0.25)
    }

    static func contentFade(_ reduceMotion: Bool, presented: Bool) -> Animation {
        if presented {
            return fade(reduceMotion)
        }

        return reduceMotion ? .linear(duration: 0.08) : .linear(duration: 0.14)
    }
}

private enum LeaveKind {
    case busyWriting
    case busySaving
    case discard
}

struct ComposeSheetView: View {
    @Bindable var viewModel: HomeViewModel
    var isActive: Bool = true
    var isOnboardingTaste: Bool = false
    var storeKitManager: StoreKitManager?
    var identityStore: ProfileIdentityStore? = nil
    var onClose: () -> Void = {}
    var onShowMembership: () -> Void = {}
    var onSave: (HomeCard) -> Void = { _ in }
    var onPresentSaveCover: (String) -> Void = { _ in }
    var onDismissSaveCover: (UUID) -> Void = { _ in }
    var needsTermsAcceptance: Bool = false
    var onAcceptTerms: () async -> Bool = { true }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var composerGlowColor: Color { InspireMark.brandColor }
    @FocusState private var composerFocused: Bool
    /// Where the header ends and the bottom bar starts. Held in a reference so a keyboard sliding\n    /// (a new value every frame) redraws only the thread's mask, never the thread.
    @State private var edges = ComposeEdges()
    @State private var showRestartAlert = false
    @State private var showLeaveAlert = false
    @State private var leaveKind: LeaveKind = .discard
    @State private var isCelebratingSave = false
    @State private var showsAIConsent = false
    /// Where the bottom bar (input, Start new, or the taste Save bar) starts, in screen
    /// coordinates. It moves with the keyboard and with the bar's own height, so it decides
    /// where the thread fades out above it.
    /// The bar's own height (input, Post, or the held place), so the thread's last row stops above it.
    @State private var bottomBarExtent: CGFloat = 72
    /// A short window after a row arrives in which the thread keeps its end in view while the
    /// new row settles to its final height (the card's caption, the keyboard going down).
    @State private var followsEndUntil = Date.distantPast

    private var isComposing: Bool {
        viewModel.phase == .composing
    }

    private var hasStatement: Bool {
        !viewModel.statement.isEmpty
    }

    private let edgePad: CGFloat = 20
    /// One short, soft ease for a row arriving. Rows already on screen never take part in it.
    private let insertAnimation = Animation.smooth(duration: 0.35)


    var body: some View {
        let _ = RenderCounter.hit("ComposeSheet")
        sessionLayout
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.cookHaptic)
            .onAppear {
                composerFocused = isActive && isComposing
            }
            .onChange(of: isActive) { _, active in
                if active {
                    isCelebratingSave = false
                    composerFocused = viewModel.phase == .composing
                    if isOnboardingTaste {
                        storeKitManager?.clearError()
                    }
                } else {
                    composerFocused = false
                    resetAfterDismiss()
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                if isActive, newPhase == .composing || newPhase == .awaitingReply {
                    composerFocused = true
                }
                // New angles arrive with the keyboard down, so it never sits over a new card.
                if case .ready = newPhase {
                    composerFocused = false
                }
            }
            .alert("Start again?", isPresented: $showRestartAlert) {
                Button("Start again", role: .destructive, action: restartSession)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(restartMessage)
            }
            .alert(leaveTitle, isPresented: $showLeaveAlert) {
                // A save that already reached the server lands either way, so there is no
                // honest "leave" while it runs; it finishes within the 6s write timeout.
                if leaveKind == .busySaving {
                    Button("OK", role: .cancel) {}
                } else {
                    Button(leaveConfirmTitle, role: .destructive, action: confirmLeave)
                    Button(leaveCancelTitle, role: .cancel) {}
                }
            } message: {
                Text(leaveMessage)
            }
            .sheet(isPresented: $showsAIConsent) {
                AIConsentSheet(
                    onAgree: {
                        guard await onAcceptTerms() else {
                            return false
                        }
                        showsAIConsent = false
                        submit(termsJustAccepted: true)
                        return true
                    },
                    onCancel: {
                        showsAIConsent = false
                    }
                )
                .interactiveDismissDisabled()
            }
    }

    private var restartMessage: String {
        if viewModel.isSessionBusy {
            return "A cook is still running and will be cancelled. This wipes these thoughts and their answers. You can’t undo it."
        }
        return "This wipes these thoughts and their answers. You can’t undo it."
    }

    private var leaveTitle: String {
        switch leaveKind {
        case .busyWriting:
            return "This is still writing. Leave anyway?"
        case .busySaving:
            return "Still saving"
        case .discard:
            return "Discard this thought?"
        }
    }

    private var leaveMessage: String {
        switch leaveKind {
        case .busyWriting:
            return "The answers are not ready yet. Leaving cancels this cook."
        case .busySaving:
            return "This takes a few seconds. You can close once the card is saved."
        case .discard:
            return "These thoughts and their answers will be gone."
        }
    }

    private var leaveConfirmTitle: String {
        leaveKind == .discard ? "Discard" : "Leave"
    }

    private var leaveCancelTitle: String {
        leaveKind == .discard ? "Keep" : "Keep going"
    }

    private var sessionLayout: some View {
        canvas
            .overlay { welcomeHero }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
    }

    private var header: some View {
        Group {
            if showsTwoLineRestore {
                restoreHeader
            } else {
                standardHeader
            }
        }
        .padding(.horizontal, edgePad)
        .padding(.top, 6)
        .padding(.bottom, showsTwoLineRestore ? 12 : 10)
        .animation(onboardingRestoreAnimation, value: storeKitManager?.errorMessage)
        .animation(onboardingRestoreAnimation, value: storeKitManager?.priorMembershipProductID)
        .task(id: showsOnboardingRestore) {
            guard showsOnboardingRestore else {
                return
            }
            await storeKitManager?.probeSubscriptionOffer()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { edges.header = $0 }
    }

    private var onboardingRestoreAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)
    }

    private var onboardingRestoreSwapTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 10).combined(with: .opacity),
            removal: .offset(y: -8).combined(with: .opacity)
        )
    }

    private var showsTwoLineRestore: Bool {
        showsOnboardingRestore
            && (storeKitManager?.hasEndedMembership == true || hasOnboardingRestoreError)
    }

    private var standardHeader: some View {
        ViewThatFits(in: .horizontal) {
            standardHeaderRow

            standardHeaderStacked
        }
    }

    private var standardHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            headerLeadingControl

            Spacer(minLength: 0)

            if hasStatement, !isOnboardingTaste {
                startAgainButton
            }

            usageStatusLine
        }
        .frame(minHeight: 40)
    }

    private var standardHeaderStacked: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                headerLeadingControl
                Spacer(minLength: 0)
                usageStatusLine
            }
            .frame(minHeight: 40)

            if hasStatement, !isOnboardingTaste {
                startAgainButton
            }
        }
    }

    private var startAgainButton: some View {
        Button("Start again") {
            showRestartAlert = true
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.ink)
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.4 : 1)
        .accessibilityHint("Wipes this session and starts a new thought")
    }

    private var restoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                restoreHeadline
                    .frame(maxWidth: .infinity, alignment: .leading)

                usageStatusLine
            }
            .frame(minHeight: 40)

            if storeKitManager?.hasEndedMembership == true {
                restoreRenewButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var restoreHeadlineText: String {
        if storeKitManager?.hasEndedMembership == true {
            return storeKitManager?.errorMessage ?? "We found your previous subscription."
        }
        return storeKitManager?.errorMessage ?? ""
    }

    private var restoreHeadline: some View {
        Text(restoreHeadlineText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.muted)
            .lineSpacing(4)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var restoreRenewButton: some View {
        Button {
            guard storeKitManager?.isBusy != true else {
                return
            }
            composerFocused = false
            onShowMembership()
        } label: {
            Text("Renew membership")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .link))
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager?.isBusy == true)
        .accessibilityLabel("View membership options")
        .transition(onboardingRestoreSwapTransition)
    }

    private var headerLeadingControl: some View {
        Group {
            if showsCloseButton {
                Button(action: requestLeave) {
                    CircleIcon(
                        systemName: "xmark",
                        fill: theme.surface,
                        symbol: theme.ink,
                        weight: .semibold,
                        hairline: theme.cardHairline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close without saving")
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
        }
    }

    private var hasOnboardingRestoreError: Bool {
        guard let errorMessage = storeKitManager?.errorMessage, !errorMessage.isEmpty else {
            return false
        }
        return storeKitManager?.hasEndedMembership != true
    }

    @ViewBuilder
    private var usageStatusLine: some View {
        if let status = viewModel.usageStatus {
            Text(status)
                .font(.caption.weight(viewModel.usageSummary?.warning == .critical ? .semibold : .medium))
                .foregroundStyle(
                    viewModel.usageSummary?.warning == .critical ? theme.ink : theme.muted
                )
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(status)
        }
    }

    @ViewBuilder
    private var welcomeHero: some View {
        if isComposing && !hasStatement {
            VStack(spacing: 20) {
                InspireMark(size: 56)

                VStack(spacing: 8) {
                    Text(welcomeTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .tracking(-0.4)

                    Text(welcomeDetail)
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)

                    if isOnboardingTaste {
                        Text("Your first thought is free.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }

    private var welcomeTitle: String {
        isOnboardingTaste ? "Welcome to Angles" : "Break the spiral."
    }

    private var welcomeDetail: String {
        if isOnboardingTaste {
            return "Write down a thought that keeps looping in your head. Angles may ask a quick follow-up, then shows it to you from a few new angles."
        }
        return "When a thought keeps looping in your head, see it from another angle."
    }

    private var canvas: some View {
        thread
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mask { ThreadMask(edges: edges).ignoresSafeArea() }
            .background(alignment: .bottom) {
                // Behind the thread, so it can never tint or cover a line of text.
                composerGlow
                    .offset(y: 132)
            }
    }

    /// The input and the bottom buttons are 56 pt tall with 8 pt above and below.
    private static let bottomBarHeight: CGFloat = 72
    fileprivate static let bottomFade: CGFloat = 36
    fileprivate static let belowBarShade = Color.black.opacity(0.14)
    fileprivate static let topFade: CGFloat = 20

    /// Every row of the thread, top to bottom. A row keeps its id for as long as it exists (the
    /// open question keeps it when it is answered), so only a row that is really new animates.
    private enum ThreadRowKind {
        case statement
        case question(RefineTurn)
        case reply(RefineTurn)
        case cooking
        case angles(ReadyCook)
        case error(String)
    }

    private struct ThreadRow: Identifiable {
        let id: String
        let kind: ThreadRowKind
    }

    private var threadRows: [ThreadRow] {
        guard hasStatement else {
            return []
        }
        var rows = [ThreadRow(id: "statement", kind: .statement)]
        for turn in viewModel.turns where turn.isAnswered {
            rows.append(ThreadRow(id: "q-\(turn.id)", kind: .question(turn)))
            if turn.reply != nil {
                rows.append(ThreadRow(id: "a-\(turn.id)", kind: .reply(turn)))
            }
        }
        switch viewModel.phase {
        case .composing:
            break
        case .awaitingReply:
            if let turn = viewModel.openTurn {
                rows.append(ThreadRow(id: "q-\(turn.id)", kind: .question(turn)))
            }
        case .cooking:
            rows.append(ThreadRow(id: "cooking", kind: .cooking))
        case .ready(let cook):
            rows.append(ThreadRow(id: "angles", kind: .angles(cook)))
        case .error(let message):
            rows.append(ThreadRow(id: "error", kind: .error(message)))
        }
        return rows
    }

    /// Top-down: the thought sits at the top and each new row goes below it. While the thread
    /// fits, nothing scrolls and the rows already there do not move. Once it is taller, one short
    /// scroll keeps the end in view. It runs under the header and the bottom bar and dissolves
    /// there (`threadMask`).
    private var thread: some View {
        let rows = threadRows
        let ids = rows.map(\.id)

        return GeometryReader { window in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(rows) { row in
                            threadRow(row)
                        }

                        Color.clear.frame(height: 0).id("thread-end")
                    }
                    .padding(.horizontal, edgePad)
                    .padding(.top, 4)
                    // The thread runs under the bar; its last row stops above the bar and its fade.
                    .padding(.bottom, bottomBarExtent + Self.bottomFade + 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                        guard Date.now < followsEndUntil else {
                            return
                        }
                        proxy.scrollTo("thread-end", anchor: .bottom)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: window.size.height,
                        alignment: .topLeading
                    )
                    .animation(reduceMotion ? nil : insertAnimation, value: ids)
                }
                .defaultScrollAnchor(.top)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture(perform: handleCanvasTap)
                .onChange(of: ids) { old, new in
                    // Only when a row was added; a row going away never scrolls.
                    guard new.count > old.count else {
                        return
                    }
                    followsEndUntil = Date.now.addingTimeInterval(1.0)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                        proxy.scrollTo("thread-end", anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let rowSpacing: CGFloat = 14

    @ViewBuilder
    private func threadRow(_ row: ThreadRow) -> some View {
        let _ = RenderCounter.hit("ThreadRow \(row.id.prefix(2))")
        switch row.kind {
        case .statement:
            userBubble(viewModel.statement, isFirst: true)
                .transition(arrival(from: .trailing))
        case .question(let turn):
            turnBlock(turn)
                .transition(arrival(from: .leading))
        case .reply(let turn):
            userBubble(turn.reply ?? "", isFirst: false)
                .transition(arrival(from: .trailing))
        case .cooking:
            cookingRow
                .transition(arrival(from: .leading))
        case .angles(let cook):
            anglesRow(cook: cook)
                .transition(arrival(from: .leading))
                .task {
                    guard !isOnboardingTaste else {
                        return
                    }
                    await SaveRide.preload(dark: colorScheme == .dark)
                }
        case .error(let message):
            errorRow(message)
                .transition(arrival(from: .leading))
        }
    }

    /// The one card, on the AI's side with its avatar at the tail, then a caption and a quiet
    /// Start new under it. Post is not here: it stays anchored at the bottom of the screen.
    private func anglesRow(cook: ReadyCook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                aiAvatar

                OverlayProposalCard(
                    thought: cook.thought,
                    thoughtOriginal: cook.thoughtOriginal,
                    results: cook.results.map(\.result),
                    recookingStyle: viewModel.recookingStyle,
                    identityStore: identityStore,
                    isPublic: $viewModel.composeIsPublic,
                    showsPrivacyToggle: !isOnboardingTaste,
                    allowsRecook: !isOnboardingTaste && viewModel.hasCreditsForCook,
                    onRecook: { style in
                        viewModel.recookStyle(style)
                    }
                )
                .id("overlay-proposal")
                .accessibilityIdentifier("compose.card")
            }

            VStack(alignment: .leading, spacing: 6) {
                if let notice = viewModel.recookNotice {
                    Text(notice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let feedback = viewModel.usageFeedback {
                    Text(feedback)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .accessibilityLabel(feedback)
                }

                if !isOnboardingTaste {
                    Button {
                        showRestartAlert = true
                    } label: {
                        Text("Start new")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSaving || isCelebratingSave)
                    .accessibilityIdentifier("compose.startNew")
                }
            }
            .padding(.leading, Self.aiAvatarColumn)
        }
    }

    /// A `continue` turn: what the AI said, plus optional chips while it is unanswered.
    private func turnBlock(_ turn: RefineTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                aiAvatar

                VStack(alignment: .leading, spacing: 8) {
                    Text(turn.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if turn.safety.needsCare {
                        Text(turn.crisisResource ?? SafetyFlag.unknownRegionCrisisLine)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("compose.crisis")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.surface, in: bubbleShape(isAI: true))
                .shadow(color: theme.shadowSoft, radius: 6, y: 2)

                Spacer(minLength: Self.aiSideGap)
            }

            // Quick replies sit under the question, in line with the bubble, like in a chat.
            if !turn.safety.needsCare, !turn.isAnswered, !turn.options.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(turn.options.enumerated()), id: \.element) { index, option in
                        optionRow(option) {
                            viewModel.chooseOption(option)
                        }
                        .accessibilityIdentifier("compose.option.\(index)")
                    }
                }
                .padding(.leading, Self.aiAvatarColumn)
                .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(turn.message)
        .accessibilityIdentifier(turn.isAnswered ? "compose.answeredFollowup" : "compose.followup")
    }

    /// The AI avatar and the gap after it; replies line up with the bubble beside it.
    private static let aiAvatarColumn: CGFloat = 50
    /// Room kept free beside an AI bubble so it never spans the whole row.
    private static let aiSideGap: CGFloat = 36
    /// Room kept free beside the user's bubble.
    private static let userSideGap: CGFloat = 36

    private func optionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(theme.grey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// A new row fades in while sliding a little from its own side: yours from the right, the
    /// AI's from the left. It never animates out, and no other row takes part.
    private func arrival(from edge: HorizontalEdge) -> AnyTransition {
        let slide = reduceMotion ? 0 : (edge == .leading ? -16.0 : 16.0)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: slide)),
            removal: .identity
        )
    }

    /// The AI's side of the screen is always this shape: the bubble corner with a small tail at
    /// the lower left, scaled up for the longer question, error, and angles cards.
    static let aiCardShape = UnevenRoundedRectangle(
        topLeadingRadius: 24,
        bottomLeadingRadius: 6,
        bottomTrailingRadius: 24,
        topTrailingRadius: 24,
        style: .continuous
    )

    /// Something the user wrote: one fill, on the right, as wide as its text. Tapping does
    /// nothing; long-press copies.
    private func userBubble(_ text: String, isFirst: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: Self.userSideGap)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.paper)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.ink, in: bubbleShape(isAI: false))
                .contentShape(bubbleShape(isAI: false))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(text)
                .accessibilityIdentifier(isFirst ? "compose.thought" : "compose.answer")

            userAvatar
                .padding(.leading, 10)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var userAvatar: some View {
        AuthorMark(
            initials: identityStore?.avatarLetters ?? identityStore?.serverInitials ?? UserInitials.letters,
            avatarPath: identityStore?.avatarPath,
            prefersLocalPhoto: true,
            side: 40,
            fill: theme.ink,
            symbol: theme.paper
        )
        .accessibilityHidden(true)
    }

    private var cookingRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            CookingLine(
                ink: theme.ink,
                muted: theme.muted,
                reduceMotion: reduceMotion
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.surface, in: bubbleShape(isAI: true))
            .shadow(color: theme.shadowSoft, radius: 6, y: 2)

            Spacer(minLength: Self.aiSideGap)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.composeErrorAllowsRetry {
                    Button("Retry", action: retryRefine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(theme.surface, in: bubbleShape(isAI: true))
            .shadow(color: theme.shadowSoft, radius: 6, y: 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message)
            .accessibilityIdentifier("compose.error")

            Spacer(minLength: Self.aiSideGap)
        }
    }

    private var aiAvatar: some View {
        InspireMarkCircle(
            fill: theme.surface,
            hairline: theme.cardHairline
        )
        .accessibilityHidden(true)
    }

    private func bubbleShape(isAI: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: isAI ? 5 : 18,
            bottomTrailingRadius: isAI ? 18 : 5,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    private var showsCloseButton: Bool {
        !isOnboardingTaste
    }

    private var showsOnboardingRestore: Bool {
        isOnboardingTaste && isComposing && !hasStatement
    }

    /// The input until angles are on screen, then Post anchored here (the taste's Save bar is the
    /// same bar). While the angles are written the bar's place is held empty.
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            if viewModel.isComposerVisible {
                // Its own observation scope: typing re-renders the input alone, never the thread.
                ObservationBoundary { composer }
                    .transition(.opacity)
            } else if viewModel.canPublish {
                if let note = bottomNote {
                    noteChip(note)
                }
                saveBar
                    .transition(.opacity)
            } else {
                // Holds the bar's place, so the thread's window never changes size.
                Color.clear
                    .frame(height: Self.bottomBarHeight)
                    .accessibilityHidden(true)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { minY in
            // The thread's fade line: moves with the keyboard and with the input growing.
            edges.bottom = minY
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if height > 0 {
                bottomBarExtent = height
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: bottomMode)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: bottomNote)
    }

    private var bottomMode: Int {
        if viewModel.isComposerVisible {
            return 0
        }
        return viewModel.canPublish ? 1 : 2
    }

    /// A taste has no field, so its note sits on an opaque chip above the Save bar.
    private func noteChip(_ note: String) -> some View {
        Text(note)
            .font(.footnote.weight(.medium))
            .foregroundStyle(theme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .accessibilityLabel(note)
            .accessibilityIdentifier("compose.note")
            .transition(.opacity)
    }

    /// One short line inside the input (or on a chip above the bottom button): a failed save
    /// or a send that was refused.
    private var bottomNote: String? {
        if let saveError = viewModel.saveError {
            return saveError
        }
        return viewModel.composeNote
    }

    private var saveBar: some View {
        Button {
            publishAndLeave()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(viewModel.isSaving ? "Saving" : saveButtonTitle)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                theme.surface,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .shadow(color: theme.shadowSoft, radius: 2, y: 1)
            .shadow(
                color: theme.shadowLift,
                radius: colorScheme == .dark ? 18 : 10,
                y: colorScheme == .dark ? 0 : 4
            )
        }
        .buttonStyle(.plain)
        .disabled(saveButtonIsBusy)
        .opacity(saveButtonIsBusy ? 0.55 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityLabel(saveButtonTitle)
        .accessibilityIdentifier("compose.post")
        .modifier(AccessibilityHintIfPresent(hint: saveButtonHint))
    }

    private var saveButtonIsBusy: Bool {
        viewModel.isSaving || isCelebratingSave || (!isOnboardingTaste && !viewModel.canPostCook)
    }

    private var saveButtonTitle: String {
        if isOnboardingTaste {
            return "Save to private library"
        }
        return viewModel.composeIsPublic ? "Post" : "Save privately"
    }

    private var saveButtonHint: String {
        if isOnboardingTaste {
            return ""
        }
        return viewModel.composeIsPublic
            ? "Posts this card on Home"
            : "Saves this card on Profile"
    }

    private var composer: some View {
        composerBar
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    private var composerGlow: some View {
        EllipticalGradient(
            stops: [
                .init(
                    color: composerGlowColor.opacity(colorScheme == .dark ? 0.16 : 0.10),
                    location: 0
                ),
                .init(
                    color: composerGlowColor.opacity(colorScheme == .dark ? 0.07 : 0.045),
                    location: 0.42
                ),
                .init(
                    color: composerGlowColor.opacity(colorScheme == .dark ? 0.02 : 0.015),
                    location: 0.72
                ),
                .init(color: .clear, location: 1),
            ],
            center: UnitPoint(x: 0.5, y: 0.58),
            startRadiusFraction: 0.08,
            endRadiusFraction: 1
        )
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .offset(y: 12)
        .blur(radius: 22)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Dark keyboard chrome is near #2B2B2A; keep the field in that family so they read as one slab.
    private var composerFill: Color {
        if colorScheme == .dark {
            return Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2A / 255)
        }
        return theme.surface
    }

    private var composerPlaceholder: String {
        viewModel.openTurn == nil ? "Tell me what's on your mind..." : "Your answer..."
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The note lives inside the pill, on its opaque fill, so it can never be read
            // through the thread scrolling behind it.
            if let note = bottomNote {
                Text(note)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .accessibilityLabel(note)
                    .accessibilityIdentifier("compose.note")
                    .transition(.opacity)
            }

            HStack(alignment: .center, spacing: 0) {
                TextField(
                    composerPlaceholder,
                    text: $viewModel.composeText,
                    axis: .vertical
                )
                .font(.body.weight(.medium))
                .foregroundStyle(theme.ink)
                .textInputAutocapitalization(.sentences)
                .focused($composerFocused)
                .accessibilityIdentifier("compose.input")
                .lineLimit(1...4)
                .frame(minHeight: 28, alignment: .leading)
                .padding(.leading, 18)
                .padding(.vertical, bottomNote == nil ? 16 : 10)

                trailingControls
            }
            .frame(minHeight: 56)
        }
        .background(
            composerFill,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 0.5)
        }
        .shadow(color: theme.shadowSoft, radius: 2, y: 1)
        .shadow(
            color: theme.shadowLift,
            radius: colorScheme == .dark ? 18 : 10,
            y: colorScheme == .dark ? 0 : 4
        )
    }

    private var trailingControls: some View {
        HStack(spacing: 0) {
            if composerFocused {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }

            Button {
                submit()
            } label: {
                CircleIcon(
                    systemName: "arrow.up",
                    fill: theme.ink,
                    symbol: theme.paper,
                    weight: .semibold
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.35)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("compose.send")
        }
        .padding(8)
    }

    private func handleCanvasTap() {
        if isOnboardingTaste {
            dismissKeyboard()
            return
        }
        if isComposing && !hasStatement {
            requestLeave()
        } else {
            dismissKeyboard()
        }
    }

    private func dismissKeyboard() {
        composerFocused = false
    }

    private func requestLeave() {
        #if DEBUG
        print("COMPOSE requestLeave phase=\(viewModel.phase) saving=\(viewModel.isSaving)")
        #endif
        if isOnboardingTaste {
            return
        }
        if viewModel.isSaving {
            leaveKind = .busySaving
            showLeaveAlert = true
            return
        }
        if viewModel.isSessionBusy {
            leaveKind = .busyWriting
            showLeaveAlert = true
            return
        }
        if viewModel.hasSessionWork {
            leaveKind = .discard
            showLeaveAlert = true
            return
        }
        confirmLeave()
    }

    private func confirmLeave() {
        onClose()
    }

    private func publishAndLeave() {
        guard !viewModel.isSaving, !isCelebratingSave, viewModel.canPublish else {
            return
        }

        Task {
            guard let savedCard = await viewModel.saveCook(
                forcePrivate: isOnboardingTaste
            ) else {
                return
            }
            if isOnboardingTaste {
                onSave(savedCard)
                return
            }

            isCelebratingSave = true
            let label = savedCard.isPublic ? "Posted" : "Saved privately"
            onPresentSaveCover(label)
            viewModel.landSavedCard(savedCard, animated: false)
            onSave(savedCard)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 400 : 1600))
            onDismissSaveCover(savedCard.id)
        }
    }

    private func restartSession() {
        viewModel.resetCompose()
        composerFocused = true
    }

    private func resetAfterDismiss() {
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 250))
            } catch {
                return
            }
            viewModel.resetCompose()
        }
    }

    /// `termsJustAccepted` because this view's copy of `needsTermsAcceptance` is the one from
    /// before the agreement landed.
    private func submit(termsJustAccepted: Bool = false) {
        #if DEBUG
        print("COMPOSE submit canSubmit=\(viewModel.canSubmit) phase=\(viewModel.phase) busy=\(viewModel.isSessionBusy) credits=\(viewModel.hasCreditsForCook)")
        #endif
        guard viewModel.canSubmit else {
            return
        }

        composerFocused = false
        if needsTermsAcceptance, !termsJustAccepted {
            showsAIConsent = true
            return
        }
        viewModel.sendComposer()
    }

    private func retryRefine() {
        viewModel.retryRefine()
    }
}

private struct CookingLine: View {
    var ink: Color
    var muted: Color
    var reduceMotion: Bool

    @State private var lineIndex = 0
    @State private var stillWorking = false

    private static let lines = [
        "Reading it",
        "Finding the sting",
        "Writing four angles",
        "Almost there",
        "Still working on it",
    ]
    /// The lines that cycle by themselves. The last one only appears when a cook runs long.
    private static let cyclingLines = 4
    private static let stillWorkingAfter: Duration = .seconds(8)

    private var stem: String {
        Self.lines[visibleLineIndex]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .opacity(index == visibleLineIndex ? 1 : 0)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ink)
        }
        .task {
            let started = ContinuousClock.now
            if !reduceMotion {
                await cycleLines()
            }
            // A cook can take 9 s or more. Say so, so a long wait never reads as frozen.
            try? await Task.sleep(until: started + Self.stillWorkingAfter, clock: .continuous)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                stillWorking = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stem)
        .accessibilityIdentifier("compose.cooking")
    }

    private var visibleLineIndex: Int {
        if stillWorking {
            return Self.lines.count - 1
        }
        return reduceMotion ? Self.lines.firstIndex(of: "Writing four angles") ?? 0 : lineIndex
    }

    private func cycleLines() async {
        while !Task.isCancelled, lineIndex < Self.cyclingLines - 1 {
            do {
                try await Task.sleep(for: .milliseconds(1400))
            } catch {
                break
            }
            withAnimation(.easeInOut(duration: 0.45)) {
                lineIndex += 1
            }
        }
    }
}

private struct AccessibilityHintIfPresent: ViewModifier {
    let hint: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if hint.isEmpty {
            content
        } else {
            content.accessibilityHint(hint)
        }
    }
}

/// One unzip of the ride per appearance, started while the answer is on screen, shared with
/// the cover. The dark file is the same animation recolored by `scripts/lottie-dark-variant.mjs`.
@MainActor
private enum SaveRide {
    private static var loading: [Bool: Task<DotLottieFile?, Never>] = [:]

    static func preload(dark: Bool) async {
        _ = await load(dark: dark)
    }

    static func load(dark: Bool) async -> DotLottieFile? {
        if let task = loading[dark] {
            return await task.value
        }
        let name = dark ? "Go to school dark" : "Go to school"
        let task = Task { try? await DotLottieFile.named(name) }
        loading[dark] = task
        return await task.value
    }

    /// Drops the unzipped files once the cover is gone; the next answer preloads again.
    static func release() {
        loading.removeAll()
    }
}

struct SaveCelebrationCover: View {
    let label: String
    var playsAnimation: Bool
    var safeAreaInsets: EdgeInsets
    var size: CGSize

    @Environment(\.colorScheme) private var colorScheme

    /// The file is a 1200 square. The rider occupies x 228...900, y 424...1029, so the
    /// artboard center is empty sky. These bounds are the bike, which is what we center.
    private static let canvas: CGFloat = 1200
    private static let scene = CGRect(x: 228, y: 424, width: 672, height: 605)

    var body: some View {
        let safeWidth = max(size.width - safeAreaInsets.leading - safeAreaInsets.trailing, 1)
        let safeHeight = max(size.height - safeAreaInsets.top - safeAreaInsets.bottom, 1)
        let sceneAspect = Self.scene.width / Self.scene.height
        let targetWidth = min(safeWidth * 0.86, safeHeight * 0.58 * sceneAspect)
        let side = targetWidth * (Self.canvas / Self.scene.width)
        let sceneCenter = CGPoint(
            x: Self.scene.midX / Self.canvas * side,
            y: Self.scene.midY / Self.canvas * side
        )
        let screenCenter = CGPoint(
            x: safeAreaInsets.leading + safeWidth / 2,
            y: safeAreaInsets.top + safeHeight / 2
        )

        ZStack {
            StyleWash.headerGlassFill(fromInk: .clear, toInk: .clear, progress: 0)

            if playsAnimation {
                let dark = colorScheme == .dark
                LottieView {
                    await SaveRide.load(dark: dark)
                }
                .playing()
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .id(dark)
                .position(
                    x: screenCenter.x - (sceneCenter.x - side / 2),
                    y: screenCenter.y - (sceneCenter.y - side / 2)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onDisappear { SaveRide.release() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("save.cover")
    }
}

/// Runs `content` in its own `body`, so the `@Observable` properties it reads (the text being
/// typed) invalidate this view only, not the screen that built it.
private struct ObservationBoundary<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

/// Screen positions of the header's bottom edge and the bottom bar's top edge.
@Observable
private final class ComposeEdges {
    var header: CGFloat = 119
    var bottom: CGFloat = 0
}

/// The thread dissolves under the header and, mirrored, just above the bottom bar, so a bubble
/// never reaches the input: it is gone before it gets there. It reads the edges itself, so only
/// this view redraws when they move.
private struct ThreadMask: View {
    let edges: ComposeEdges

    var body: some View {
        GeometryReader { geo in
            let height = max(geo.size.height, 1)
            let topEnd = min(max(edges.header / height, 0.02), 0.5)
            let topStart = max(topEnd - ComposeSheetView.topFade / height, 0.005)
            let bottomEnd = edges.bottom > 0
                ? min(max((edges.bottom - geo.frame(in: .global).minY) / height, topEnd + 0.01), 1)
                : 1
            let bottomStart = max(bottomEnd - ComposeSheetView.bottomFade / height, topEnd + 0.005)
            let below = bottomEnd < 1 ? ComposeSheetView.belowBarShade : Color.black

            LinearGradient(
                stops: [
                    // Nothing is drawn under the header buttons: no text over text.
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: topStart),
                    .init(color: .black, location: topEnd),
                    .init(color: .black, location: bottomStart),
                    // Not solid: what is scrolled under the bar stays faintly visible.
                    .init(color: below, location: bottomEnd),
                    .init(color: below, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    ZStack {
        AnglesCanvasBackground()
        ComposeFrost()
        ComposeSheetView(viewModel: HomeViewModel(), onClose: {})
    }
}
