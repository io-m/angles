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
    @FocusState private var writeNewFocused: Bool
    @State private var scrollToken = 0
    @State private var headerStrip: CGFloat = 119
    @State private var showRestartAlert = false

    private var isComposing: Bool {
        viewModel.phase == .composing
    }

    private var hasStatement: Bool {
        !viewModel.statement.isEmpty
    }

    private let edgePad: CGFloat = 20
    private let insertAnimation = Animation.easeOut(duration: 0.32)
    private let writeNewLabel = "Write something new"

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
                    writeNewFocused = viewModel.isWritingNew
                } else {
                    composerFocused = false
                    writeNewFocused = false
                    resetAfterDismiss()
                }
            }
            .onChange(of: viewModel.phase) { _, newPhase in
                scrollToken += 1
                if isActive, newPhase == .composing {
                    composerFocused = true
                }
            }
            .onChange(of: viewModel.isWritingNew) { _, writing in
                writeNewFocused = writing && isActive
                scrollToken += 1
            }
            .onChange(of: viewModel.clarifyRounds) { _, _ in
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

            Spacer()

            if hasStatement {
                Button("Start again") {
                    showRestartAlert = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .accessibilityHint("Wipes this session and starts a new thought")
            }
        }
        .padding(.horizontal, edgePad)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { headerStrip = $0 }
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

                        ForEach(viewModel.clarifyRounds) { round in
                            clarifyBlock(round)
                                .transition(insertTransition(isAI: true))
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
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.clarifyRounds)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.isWritingNew)
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
        case .composing, .awaitingClarify:
            EmptyView()
        case .cooking:
            cookingRow
                .transition(insertTransition(isAI: true))
        case .ready(let results):
            HStack(alignment: .bottom, spacing: 10) {
                aiAvatar

                OverlayProposalCard(
                    thought: viewModel.statement,
                    results: results,
                    onRecook: { style in
                        viewModel.recookStyle(style)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("overlay-proposal")
            }
            .transition(insertTransition(isAI: true))
        case .error(let message):
            errorRow(message)
                .transition(insertTransition(isAI: true))
        }
    }

    private func clarifyBlock(_ round: ClarifyRound) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 12) {
                Text(round.question)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    ForEach(round.options, id: \.self) { option in
                        optionRow(
                            option,
                            state: optionState(option, in: round)
                        ) {
                            viewModel.answerClarify(option)
                        }
                    }

                    writeNewRow(for: round)
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
        .accessibilityLabel(round.question)
    }

    private func optionState(_ option: String, in round: ClarifyRound) -> OptionRowState {
        guard let selected = round.selectedAnswer else {
            return .idle
        }

        if !round.selectedIsCustom, selected == option {
            return .chosen
        }

        return .rejected
    }

    private enum OptionRowState {
        case idle
        case chosen
        case rejected
    }

    private func optionRow(
        _ title: String,
        state: OptionRowState,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(state == .chosen ? .semibold : .medium))
                .strikethrough(state == .rejected)
                .foregroundStyle(state == .rejected ? theme.muted : theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(optionBackground(state), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
        .accessibilityAddTraits(state == .chosen ? .isSelected : [])
    }

    private func optionBackground(_ state: OptionRowState) -> Color {
        switch state {
        case .idle:
            return theme.grey
        case .chosen:
            return theme.ink.opacity(colorScheme == .dark ? 0.22 : 0.08)
        case .rejected:
            return theme.grey.opacity(0.55)
        }
    }

    @ViewBuilder
    private func writeNewRow(for round: ClarifyRound) -> some View {
        if round.isAnswered {
            if round.selectedIsCustom, let answer = round.selectedAnswer {
                optionRow(answer, state: .chosen, action: {})
            } else {
                optionRow(writeNewLabel, state: .rejected, action: {})
            }
        } else if viewModel.isWritingNew {
            HStack(alignment: .center, spacing: 8) {
                TextField(writeNewLabel, text: $viewModel.writeNewText, axis: .vertical)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .textInputAutocapitalization(.sentences)
                    .focused($writeNewFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit(submitWriteNew)

                Button(action: submitWriteNew) {
                    CircleIcon(
                        systemName: "arrow.up",
                        fill: theme.ink,
                        symbol: theme.paper,
                        weight: .semibold
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmitWriteNew)
                .opacity(viewModel.canSubmitWriteNew ? 1 : 0.35)
                .accessibilityLabel("Send")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(theme.grey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            optionRow(writeNewLabel, state: .idle) {
                viewModel.beginWriteNew()
            }
        }
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
        if isComposing {
            composer
        } else if viewModel.canPublish {
            saveBar
        }
    }

    private var saveBar: some View {
        Button(action: publishAndLeave) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                Text("Save")
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

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            TextField(
                "Tell me what's on your mind...",
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
        writeNewFocused = false
    }

    private func leaveNow() {
        onClose()
    }

    private func publishAndLeave() {
        guard viewModel.canPublish else {
            return
        }

        viewModel.publishSelected()
        onSave()
        onClose()
    }

    private func restartSession() {
        viewModel.resetCompose()
        composerFocused = true
        writeNewFocused = false
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
            viewModel.submitStatement()
        }
    }

    private func submitWriteNew() {
        guard viewModel.canSubmitWriteNew else {
            return
        }

        writeNewFocused = false
        withAnimation(insertAnimation) {
            viewModel.submitWriteNew()
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
