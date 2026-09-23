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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var composerGlowColor: Color { viewModel.selectedModel.brandColor }
    @FocusState private var composerFocused: Bool
    @State private var headerStrip: CGFloat = 119
    @State private var showRestartAlert = false
    @State private var showLeaveAlert = false
    @State private var leaveKind: LeaveKind = .discard
    @State private var showModelPicker = false
    @State private var isCelebratingSave = false

    private var isComposing: Bool {
        viewModel.phase == .composing
    }

    private var hasStatement: Bool {
        !viewModel.statement.isEmpty
    }

    private let edgePad: CGFloat = 20
    private let insertAnimation = Animation.easeInOut(duration: 0.38)

    private var threadCue: ThreadCue {
        ThreadCue(
            phase: viewModel.phase,
            turnCount: viewModel.turns.count,
            hasStatement: hasStatement
        )
    }

    var body: some View {
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
    }

    private var restartMessage: String {
        if viewModel.isSessionBusy {
            return "A cook is still running and will be cancelled. This wipes the current thought and answers. You can’t undo it."
        }
        return "This wipes the current thought and answers. You can’t undo it."
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
            return "This thought and its answers will be gone."
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
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .overlay { welcomeHero }
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
        } action: { headerStrip = $0 }
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
        HStack(alignment: .center, spacing: 12) {
            headerLeadingControl
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)

            HStack(spacing: 12) {
                if hasStatement, !isOnboardingTaste {
                    Button("Start again") {
                        showRestartAlert = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .disabled(viewModel.isSaving)
                    .opacity(viewModel.isSaving ? 0.4 : 1)
                    .accessibilityHint("Wipes this session and starts a new thought")
                }

                modelPickerButton
            }
        }
        .frame(minHeight: 40)
    }

    private var restoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                restoreHeadline
                    .frame(maxWidth: .infinity, alignment: .leading)

                modelPickerButton
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
            } else if showsOnboardingRestore {
                onboardingAccountLink
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

    private var modelPickerButton: some View {
        Button {
            showModelPicker = true
        } label: {
            ModelLogoButton(
                model: viewModel.selectedModel,
                fill: theme.surface,
                hairline: theme.cardHairline
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isModelLocked)
        .opacity(viewModel.isModelLocked ? 0.45 : 1)
        .accessibilityLabel("Model")
        .accessibilityValue(viewModel.selectedModel.displayName)
        .popover(isPresented: $showModelPicker, arrowEdge: .top) {
            modelPicker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LlmModel.allCases) { model in
                let isSelected = viewModel.selectedModel == model

                Button {
                    viewModel.selectedModel = model
                    showModelPicker = false
                } label: {
                    HStack(spacing: 12) {
                        ModelLogo(model: model, side: 18)
                            .frame(width: 22, alignment: .center)

                        Text(model.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.ink)

                        Spacer(minLength: 12)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.ink)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)

                if model != LlmModel.allCases.last {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                        .padding(.leading, 50)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 220)
        .background(theme.surface)
    }

    @ViewBuilder
    private var welcomeHero: some View {
        if isComposing && !hasStatement {
            GeometryReader { geo in
                VStack(spacing: 20) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(theme.ink)

                    VStack(spacing: 8) {
                        Text("Break the spiral.")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .tracking(-0.4)

                        Text("When a thought keeps looping in your head, see it from another angle.")
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 28)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.38)
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Break the spiral. When a thought keeps looping in your head, see it from another angle.")
        }
    }

    private var canvas: some View {
        thread
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.18), location: 0),
                            .init(color: .black.opacity(0.45), location: 0.5),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: headerStrip)

                    Color.black
                }
                .ignoresSafeArea()
            }
    }

    private var thread: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if hasStatement {
                    userRow(viewModel.statement)
                        .transition(rowTransition)

                    ForEach(viewModel.turns) { turn in
                        turnBlock(turn)
                            .transition(rowTransition)

                        if let reply = turn.reply {
                            userRow(reply)
                                .transition(rowTransition)
                        }
                    }

                    refineTail
                }
            }
            .padding(.horizontal, edgePad)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : insertAnimation, value: threadCue)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.never)
        .contentShape(Rectangle())
        .onTapGesture(perform: handleCanvasTap)
    }

    @ViewBuilder
    private var refineTail: some View {
        switch viewModel.phase {
        case .composing, .awaitingReply:
            EmptyView()
        case .cooking:
            cookingRow
                .transition(rowTransition)
        case .ready(let cook):
            HStack(alignment: .bottom, spacing: 10) {
                aiAvatar

                VStack(alignment: .leading, spacing: 8) {
                    OverlayProposalCard(
                        thought: cook.thought,
                        thoughtOriginal: cook.thoughtOriginal,
                        results: cook.results.map(\.result),
                        recookingStyle: viewModel.recookingStyle,
                        identityStore: identityStore,
                        isPublic: $viewModel.composeIsPublic,
                        allowsRecook: !isOnboardingTaste,
                        onRecook: { style in
                            viewModel.recookStyle(style)
                        }
                    )
                    .id("overlay-proposal")

                    if let notice = viewModel.recookNotice {
                        Text(notice)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(rowTransition)
        case .error(let message):
            errorRow(message)
                .transition(rowTransition)
        }
    }

    /// A `continue` turn: what the AI said, plus optional chips while it is unanswered.
    private func turnBlock(_ turn: RefineTurn) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 12) {
                Text(turn.message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if turn.safety.needsCare {
                    Text("If you are in danger right now, call or text 988.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !turn.isAnswered, !turn.options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(turn.options, id: \.self) { option in
                            optionRow(option) {
                                viewModel.chooseOption(option)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.surface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(turn.message)
    }

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

    private var rowTransition: AnyTransition {
        .opacity.combined(with: .offset(y: 8))
    }

    private func userRow(_ text: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: 28)

            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.paper)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(theme.ink, in: bubbleShape(isAI: false))
                .frame(maxWidth: 280, alignment: .trailing)

            userAvatar
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(text)
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
            .frame(maxWidth: 280, alignment: .leading)

            Spacer(minLength: 12)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Retry", action: retryRefine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.surface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message)
        }
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
    }

    private var aiAvatar: some View {
        CircleIcon(
            systemName: "sparkle",
            fill: theme.surface,
            symbol: theme.ink,
            weight: .semibold,
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

    @ViewBuilder
    private var bottomChrome: some View {
        if viewModel.isComposerVisible {
            composer
        } else if viewModel.canPublish {
            VStack(spacing: 8) {
                if let saveError = viewModel.saveError {
                    Text(saveError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .accessibilityLabel(saveError)
                }
                saveBar
            }
        }
    }

    private var saveBar: some View {
        Button(action: publishAndLeave) {
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
        .background { composerGlow }
        .accessibilityLabel(saveButtonTitle)
        .modifier(AccessibilityHintIfPresent(hint: saveButtonHint))
    }

    private var saveButtonIsBusy: Bool {
        viewModel.isSaving || isCelebratingSave
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
            .background {
                composerGlow
            }
    }

    private var onboardingAccountLink: some View {
        let isRestoring = storeKitManager?.isRestoring == true
        return Button {
            guard let storeKitManager, !storeKitManager.isBusy else {
                return
            }
            composerFocused = false
            Task {
                _ = await storeKitManager.restorePurchases()
            }
        } label: {
            HStack(spacing: 6) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(uiColor: .link))
                }
                Text(isRestoring ? "Checking subscription…" : "Already have an account?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(uiColor: .link))
                    .lineLimit(1)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager?.isBusy == true)
        .accessibilityLabel("Restore purchases if you already subscribe")
        .accessibilityAddTraits(.isLink)
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
        viewModel.openTurn == nil ? "Tell me what's on your mind..." : "Say more..."
    }

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            TextField(
                composerPlaceholder,
                text: $viewModel.composeText,
                axis: .vertical
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(theme.ink)
            .textInputAutocapitalization(.sentences)
            .focused($composerFocused)
            .lineLimit(1...4)
            .frame(minHeight: 28, alignment: .leading)
            .padding(.leading, 18)
            .padding(.vertical, 16)

            trailingControls
        }
        .frame(minHeight: 56)
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

            Button(action: submit) {
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
        guard viewModel.canPublish, !viewModel.isSaving, !isCelebratingSave else {
            return
        }

        Task {
            guard let savedCard = await viewModel.saveCook() else {
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
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 400 : 1000))
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

    private func submit() {
        guard viewModel.canSubmit else {
            return
        }

        composerFocused = false
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

    private static let lines = [
        "Reading it",
        "Finding the sting",
        "Writing four angles",
        "Almost there",
    ]

    private var stem: String {
        reduceMotion ? "Writing four angles" : Self.lines[min(lineIndex, Self.lines.count - 1)]
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
            guard !reduceMotion else { return }
            await cycleLines()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stem)
    }

    private var visibleLineIndex: Int {
        reduceMotion ? Self.lines.firstIndex(of: "Writing four angles") ?? 0 : lineIndex
    }

    private func cycleLines() async {
        while !Task.isCancelled, lineIndex < Self.lines.count - 1 {
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

struct SaveCelebrationCover: View {
    let label: String
    var playsAnimation: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper

            if playsAnimation {
                LottieView(animation: .named("celebration-checkmark"))
                    .playing()
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

private struct ThreadCue: Equatable {
    var phase: RefinePhase
    var turnCount: Int
    var hasStatement: Bool
}

#Preview {
    ZStack {
        AnglesCanvasBackground()
        ComposeFrost()
        ComposeSheetView(viewModel: HomeViewModel(), onClose: {})
    }
}
