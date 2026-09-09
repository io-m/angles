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
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var isActive: Bool = true
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentPalette) private var accentPalette

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    @FocusState private var composerFocused: Bool
    @State private var showStylePicker = false
    @State private var scrollToken = 0
    @State private var headerStrip: CGFloat = 119

    private var hasTranscript: Bool {
        !viewModel.turns.isEmpty
    }

    private let edgePad: CGFloat = 20
    private let insertAnimation = Animation.easeOut(duration: 0.32)
    private let saveCloudAnimation = Animation.easeOut(duration: 0.14)

    var body: some View {
        chatLayout
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.cookHaptic)
            .onAppear {
                composerFocused = isActive
            }
            .onChange(of: isActive) { _, active in
                composerFocused = active
                if !active {
                    showStylePicker = false
                    resetAfterDismiss()
                }
            }
            .onChange(of: viewModel.turns) { _, _ in
                scrollToken += 1
            }
            .onChange(of: viewModel.isCooking) { _, _ in
                scrollToken += 1
            }
    }

    private var chatLayout: some View {
        canvas
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
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

            stylePill
        }
        .padding(.horizontal, edgePad)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { headerStrip = $0 }
    }

    private var stylePill: some View {
        Button {
            showStylePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: stylePillIcon)
                    .font(.system(size: 14, weight: .semibold))
                Text(stylePillLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(theme.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style")
        .accessibilityValue(stylePillLabel)
        .popover(isPresented: $showStylePicker) {
            stylePicker
                .presentationCompactAdaptation(.popover)
        }
    }

    private var stylePillIcon: String {
        CardStyleAppearance(style: viewModel.selectedStyle).systemImage
    }

    private var stylePillLabel: String {
        viewModel.selectedStyle.displayName
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Style.allCases, id: \.self) { style in
                let appearance = CardStyleAppearance(style: style)
                let isSelected = viewModel.selectedStyle == style

                Button {
                    showStylePicker = false
                    viewModel.selectStyle(style)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: appearance.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(appearance.ink)
                            .frame(width: 22, alignment: .center)

                        Text(style.displayName)
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
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var welcomeHero: some View {
        if !hasTranscript {
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
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(viewModel.turns) { turn in
                        VStack(alignment: .leading, spacing: 10) {
                            userRow(turn.thought)
                                .transition(insertTransition(isAI: false))

                            if viewModel.isCookingTurn(turn) {
                                cookingRow
                                    .transition(insertTransition(isAI: true))
                            } else if let error = turn.error {
                                errorRow(error)
                                    .transition(insertTransition(isAI: true))
                            } else if let result = turn.result {
                                resultRow(result, turnID: turn.id)
                                    .transition(insertTransition(isAI: true))
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("compose-end")
                }
                .padding(.horizontal, edgePad)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.turns)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.isCooking)
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

    private func resultRow(_ result: ReframeResult, turnID: UUID) -> some View {
        let appearance = CardStyleAppearance(style: result.style)
        let isSaved = viewModel.isSaved(turnID: turnID)

        return HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 8) {
                    styleIconBadge(appearance)

                    Text(result.style.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appearance.ink)
                        .lineLimit(1)
                        .frame(height: 40)

                    Spacer(minLength: 4)

                    saveCheckbox(isSaved: isSaved, ink: appearance.ink) {
                        viewModel.toggleSave(turnID: turnID)
                    }
                }

                Text(result.reframe)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                appearance.washFill(over: theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(result.style.displayName) reframe. \(result.reframe)")
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

                Button("Retry", action: retryCook)
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

    private func styleIconBadge(_ appearance: CardStyleAppearance) -> some View {
        Image(systemName: appearance.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(appearance.ink)
            .frame(width: 40, height: 40)
            .background(
                appearance.ink.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func saveCheckbox(isSaved: Bool, ink: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSaved ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Deselect" : "Select to save")
        .accessibilityAddTraits(isSaved ? .isSelected : [])
    }

    private var userAvatar: some View {
        CircleIcon(
            systemName: "person.fill",
            fill: theme.ink,
            symbol: theme.paper,
            weight: .semibold
        )
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

    private var composer: some View {
        VStack(spacing: 10) {
            saveCloud
                .opacity(viewModel.canPublish ? 1 : 0)
                .scaleEffect(viewModel.canPublish ? 1 : 0.96)
                .offset(y: viewModel.canPublish ? 0 : 6)
                .allowsHitTesting(viewModel.canPublish)
                .accessibilityHidden(!viewModel.canPublish)
                .compositingGroup()

            composerBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            composerGlow
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : saveCloudAnimation,
            value: viewModel.canPublish
        )
    }

    private var saveCloud: some View {
        Button(action: publishAndLeave) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                Text("Save")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(theme.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .shadow(color: theme.shadowSoft, radius: 2, y: 1)
            .shadow(
                color: theme.shadowLift,
                radius: colorScheme == .dark ? 16 : 10,
                y: colorScheme == .dark ? 0 : 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save selected")
        .accessibilityHint("Adds checked replies to home and closes the chat")
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
        if hasTranscript {
            dismissKeyboard()
        } else {
            leaveNow()
        }
    }

    private func dismissKeyboard() {
        composerFocused = false
    }

    private func leaveNow() {
        onClose()
    }

    private func publishAndLeave() {
        guard viewModel.canPublish else {
            return
        }

        viewModel.publishSelected()
        onClose()
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

        withAnimation(insertAnimation) {
            viewModel.submitCompose(animatedDelay: !reduceMotion)
        }
    }

    private func retryCook() {
        withAnimation(insertAnimation) {
            viewModel.retryCook(animatedDelay: !reduceMotion)
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
