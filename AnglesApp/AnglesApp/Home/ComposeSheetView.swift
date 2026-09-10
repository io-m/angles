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

struct ComposeSheetView: View {
    @ObservedObject var viewModel: HomeViewModel
    var isActive: Bool = true
    var onClose: () -> Void = {}
    var onSave: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentPalette) private var accentPalette

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    @FocusState private var composerFocused: Bool
    @State private var scrollToken = 0
    @State private var headerStrip: CGFloat = 119
    @State private var showRestartAlert = false
    @State private var showModelPicker = false

    private var isComposing: Bool {
        viewModel.phase == .composing
    }

    private var hasStatement: Bool {
        !viewModel.statement.isEmpty
    }

    private let edgePad: CGFloat = 20
    private let insertAnimation = Animation.easeOut(duration: 0.32)

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
                    composerFocused = viewModel.phase == .composing
                } else {
                    composerFocused = false
                    resetAfterDismiss()
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                scrollToken += 1
                if isActive, newPhase == .composing || newPhase == .awaitingReply {
                    composerFocused = true
                }
            }
            .onChange(of: viewModel.turns) { _, _ in
                scrollToken += 1
            }
            .alert("Start again?", isPresented: $showRestartAlert) {
                Button("Start again", role: .destructive, action: restartSession)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This wipes the current thought and answers. You can’t undo it.")
            }
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
        HStack {
            Button(action: leaveNow) {
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

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if hasStatement {
                    Button("Start again") {
                        showRestartAlert = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .accessibilityHint("Wipes this session and starts a new thought")
                }

                modelPickerButton
            }
        }
        .padding(.horizontal, edgePad)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { headerStrip = $0 }
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
                    Text("Tell me what's on your mind...")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .tracking(-0.4)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.38)
            }
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tell me what's on your mind...")
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if hasStatement {
                        userRow(viewModel.statement)
                            .transition(insertTransition(isAI: false))

                        ForEach(viewModel.turns) { turn in
                            turnBlock(turn)
                                .transition(insertTransition(isAI: true))

                            if let reply = turn.reply {
                                userRow(reply)
                                    .transition(insertTransition(isAI: false))
                            }
                        }

                        refineTail
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("compose-end")
                }
                .padding(.horizontal, edgePad)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.phase)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.turns)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleCanvasTap)
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo("compose-end", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var refineTail: some View {
        switch viewModel.phase {
        case .composing, .awaitingReply:
            EmptyView()
        case .cooking:
            cookingRow
                .transition(insertTransition(isAI: true))
        case .ready(let cook):
            HStack(alignment: .bottom, spacing: 10) {
                aiAvatar

                VStack(alignment: .leading, spacing: 8) {
                    OverlayProposalCard(
                        thought: cook.thought,
                        thoughtOriginal: cook.thoughtOriginal,
                        results: cook.results,
                        recookingStyle: viewModel.recookingStyle,
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
            .transition(insertTransition(isAI: true))
        case .error(let message):
            errorRow(message)
                .transition(insertTransition(isAI: true))
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

    private func insertTransition(isAI: Bool) -> AnyTransition {
        let x: CGFloat = isAI ? -18 : 18
        return .opacity.combined(with: .offset(x: x, y: 5))
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
                text: "Cooking...",
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
        .accessibilityLabel("Cooking")
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
        InitialsAvatar(side: 40, fill: theme.ink, symbol: theme.paper)
            .accessibilityHidden(true)
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
                Text(viewModel.isSaving ? "Saving" : "Save")
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
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.55 : 1)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background { composerGlow }
        .accessibilityLabel("Save")
        .accessibilityHint("Adds all four answers to Profile and closes")
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

    private var composerGlow: some View {
        EllipticalGradient(
            stops: [
                .init(
                    color: accentPalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.10),
                    location: 0
                ),
                .init(
                    color: accentPalette.accent.opacity(colorScheme == .dark ? 0.07 : 0.045),
                    location: 0.42
                ),
                .init(
                    color: accentPalette.accent.opacity(colorScheme == .dark ? 0.02 : 0.015),
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
        if isComposing && !hasStatement {
            leaveNow()
        } else {
            dismissKeyboard()
        }
    }

    private func dismissKeyboard() {
        composerFocused = false
    }

    private func leaveNow() {
        onClose()
    }

    private func publishAndLeave() {
        guard viewModel.canPublish, !viewModel.isSaving else {
            return
        }

        Task {
            let saved = await viewModel.saveCook()
            if saved {
                onSave()
                onClose()
            }
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
        withAnimation(insertAnimation) {
            viewModel.sendComposer()
        }
    }

    private func retryRefine() {
        withAnimation(insertAnimation) {
            viewModel.retryRefine()
        }
    }
}

private struct CookingLine: View {
    var text: String
    var ink: Color
    var muted: Color
    var reduceMotion: Bool

    @State private var dotCount = 1
    @State private var sparkleOn = true

    private var stem: String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted)
                .opacity(reduceMotion ? 1 : (sparkleOn ? 1 : 0.32))
                .scaleEffect(reduceMotion ? 1 : (sparkleOn ? 1.08 : 0.88))
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text(stem)
                Text(reduceMotion ? "." : String(repeating: ".", count: dotCount))
                    .frame(width: 18, alignment: .leading)
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ink)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.36), value: sparkleOn)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(360))
                } catch {
                    break
                }
                dotCount = dotCount == 3 ? 1 : dotCount + 1
                sparkleOn.toggle()
            }
        }
        .accessibilityLabel(text)
    }
}

#Preview {
    ZStack {
        AnglesCanvasBackground()
        ComposeFrost()
        ComposeSheetView(viewModel: HomeViewModel(), onClose: {})
    }
}
