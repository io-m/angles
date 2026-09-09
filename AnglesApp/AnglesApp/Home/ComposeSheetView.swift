import SwiftUI

struct ComposeFrost: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)

            Color.anglesSurface
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
    @FocusState private var composerFocused: Bool
    @State private var showStylePicker = false
    @State private var scrollToken = 0

    private var hasTranscript: Bool {
        viewModel.submittedThought != nil
    }

    private let edgePad: CGFloat = 20
    private let insertAnimation = Animation.easeOut(duration: 0.32)

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
                    resetAfterDismiss()
                }
            }
            .onChange(of: viewModel.submittedThought) { _, _ in
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
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.anglesInk)
                    .frame(width: 44, height: 44)
                    .background(Color.anglesSurface, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.anglesHairline, lineWidth: 0.5)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()

            stylePill
        }
        .padding(.horizontal, edgePad)
        .padding(.top, safeAreaInsets.top + 6)
        .padding(.bottom, 10)
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
            .foregroundStyle(Color.anglesInk)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.anglesSurface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.anglesHairline, lineWidth: 0.5)
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
        if let style = viewModel.selectedStyle {
            return CardStyleAppearance(style: style).systemImage
        }
        return "sparkle"
    }

    private var stylePillLabel: String {
        viewModel.selectedStyle?.displayName ?? "Style"
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Style.allCases, id: \.self) { style in
                let appearance = CardStyleAppearance(style: style)
                let isSelected = viewModel.selectedStyle == style

                Button {
                    viewModel.selectStyle(style)
                    showStylePicker = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: appearance.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(appearance.ink)
                            .frame(width: 22, alignment: .center)

                        Text(style.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.anglesInk)

                        Spacer(minLength: 12)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.anglesInk)
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
                        .foregroundStyle(Color.anglesInk)
                    Text("Tell me what's on your mind...")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.anglesInk)
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
                    .frame(height: safeAreaInsets.top + 60)

                    Color.black
                }
                .ignoresSafeArea()
            }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let thought = viewModel.submittedThought {
                        userRow(thought)
                            .transition(insertTransition(isAI: false))
                    }

                    if viewModel.isCooking {
                        cookingRow
                            .transition(insertTransition(isAI: true))
                    } else if let result = viewModel.submittedResult {
                        aiRow(result)
                            .transition(insertTransition(isAI: true))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("compose-end")
                }
                .padding(.horizontal, edgePad)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.isCooking)
                .animation(reduceMotion ? nil : insertAnimation, value: viewModel.submittedResult)
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
                .foregroundStyle(Color.anglesPaper)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.anglesInk, in: bubbleShape(isAI: false))
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(text)
    }

    private var cookingRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            CookingLine(
                text: "Cooking...",
                ink: Color.anglesInk,
                muted: Color.anglesInk.opacity(0.45),
                reduceMotion: reduceMotion
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.anglesSurface, in: bubbleShape(isAI: true))
            .frame(maxWidth: 280, alignment: .leading)

            Spacer(minLength: 12)
        }
        .accessibilityLabel("Cooking")
    }

    private func aiRow(_ result: ReframeResult) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            aiAvatar

            VStack(alignment: .leading, spacing: 7) {
                Text(result.style.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.anglesAccent)

                Text(result.reframe)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.anglesInk)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.anglesSurface, in: bubbleShape(isAI: true))
            .frame(maxWidth: 280, alignment: .leading)

            Spacer(minLength: 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var aiAvatar: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.anglesInk)
            .frame(width: 40, height: 40)
            .background(Color.anglesSurface, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.anglesHairline, lineWidth: 0.5)
            }
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
        composerBar
            .padding(.horizontal, 18)
            .padding(.top, 36)
            .padding(.bottom, 8)
            .background {
                composerGlow
            }
    }

    private var composerGlow: some View {
        EllipticalGradient(
            stops: [
                .init(
                    color: Color.anglesAccent.opacity(colorScheme == .dark ? 0.16 : 0.10),
                    location: 0
                ),
                .init(
                    color: Color.anglesAccent.opacity(colorScheme == .dark ? 0.07 : 0.045),
                    location: 0.42
                ),
                .init(
                    color: Color.anglesAccent.opacity(colorScheme == .dark ? 0.02 : 0.015),
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

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            TextField(
                "Tell me what's on your mind...",
                text: $viewModel.composeText,
                axis: .vertical
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.anglesInk)
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
            Color.anglesSurface,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.anglesHairline, lineWidth: 0.5)
        }
        .shadow(color: .anglesShadowSoft, radius: 2, y: 1)
        .shadow(
            color: .anglesShadowLift,
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
                        .foregroundStyle(Color.anglesInk.opacity(0.45))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.anglesPaper)
                    .frame(width: 40, height: 40)
                    .background(Color.anglesInk, in: Circle())
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
