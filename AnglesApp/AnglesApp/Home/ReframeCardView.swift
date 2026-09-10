import SwiftUI

struct ReframeCardView: View {
    let card: HomeCard
    var onDelete: () -> Void = {}
    var onToggleFavorite: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 226
    @State private var isFlipped = false
    @State private var showingOriginal = false
    @State private var pagedSlideID: UUID?
    @State private var flipHaptic = 0
    @State private var favoriteHaptic = 0
    @State private var deleteHaptic = 0
    @State private var showDelete = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private let dotsHeight: CGFloat = 18

    private var showingThought: Bool {
        isFlipped
    }

    private var activeSlideIndex: Int {
        guard let pagedSlideID,
              let index = card.slides.firstIndex(where: { $0.id == pagedSlideID })
        else {
            return 0
        }

        return index
    }

    var body: some View {
        VStack(spacing: 8) {
            clippedCard

            pageDots
                .frame(height: dotsHeight)
                .opacity(!showingThought && card.slides.count > 1 ? 1 : 0)
                .accessibilityHidden(true)
        }
        .onAppear {
            if pagedSlideID == nil {
                pagedSlideID = card.spotlightSlideID
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: favoriteHaptic)
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showingThought ? "Shows the answers" : "Shows the original thought")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        if showingThought {
            return card.thought
        }

        if let slide = card.slides[safe: activeSlideIndex] {
            return "\(slide.result.style.displayName) answer. \(slide.result.reframe)"
        }

        return card.thought
    }

    private var clippedCard: some View {
        ZStack {
            FlipStack(progress: isFlipped ? 1 : 0) {
                answerPager
            } back: {
                thoughtFace
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            chromeOverlay
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .contentShape(cardShape)
        .onTapGesture(perform: flip)
        .onLongPressGesture(minimumDuration: 0.45) {
            deleteHaptic += 1
            showDelete = true
        }
        .popover(isPresented: $showDelete) {
            Button(role: .destructive) {
                showDelete = false
                onDelete()
            } label: {
                Text("Delete")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minWidth: 140)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var thoughtFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            InitialsAvatar(side: 32, fill: theme.ink, symbol: theme.paper)

            Text(showingOriginal ? (card.thoughtOriginal ?? card.thought) : card.thought)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
    }

    private var hasOriginal: Bool {
        guard let original = card.thoughtOriginal else {
            return false
        }

        return original != card.thought
    }

    private var answerPager: some View {
        Group {
            if card.slides.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(card.slides) { slide in
                            answerPage(slide.result)
                                .containerRelativeFrame(.horizontal)
                                .id(slide.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pagedSlideID)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else if let slide = card.slides.first {
                answerPage(slide.result)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func answerPage(_ result: ReframeResult) -> some View {
        let appearance = CardStyleAppearance(style: result.style)

        return VStack(alignment: .leading, spacing: 12) {
            stylePill(appearance)

            Text(result.reframe)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                favoriteButton
            }

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            HStack {
                Text(HomeViewModel.dateLabel(for: card.createdAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .allowsHitTesting(false)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                if showingThought && hasOriginal {
                    OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                        showingOriginal.toggle()
                    }
                }
            }
        }
        .padding(12)
    }

    private var favoriteButton: some View {
        Button {
            favoriteHaptic += 1
            onToggleFavorite()
        } label: {
            Image(systemName: card.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(card.isFavorite ? theme.ink : theme.muted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(card.isFavorite ? .isSelected : [])
    }

    private var pageDots: some View {
        let indices = visibleDotIndices
        return HStack(spacing: 5) {
            ForEach(indices, id: \.self) { index in
                let isActive = index == activeSlideIndex
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 6)
    }

    private var visibleDotIndices: [Int] {
        ReframePageDots.visibleIndices(count: card.slides.count)
    }

    private func flip() {
        flipHaptic += 1

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isFlipped.toggle()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)) {
            isFlipped.toggle()
        }
    }
}

struct OverlayProposalCard: View {
    let thought: String
    var thoughtOriginal: String?
    let results: [ReframeResult]
    var recookingStyle: Style?
    var onRecook: (Style) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 226
    @State private var isFlipped = false
    @State private var showingOriginal = false
    @State private var pagedStyle: Style?
    @State private var flipHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var showingThought: Bool {
        isFlipped
    }

    private var activeIndex: Int {
        guard let pagedStyle,
              let index = results.firstIndex(where: { $0.style == pagedStyle })
        else {
            return 0
        }

        return index
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FlipStack(progress: isFlipped ? 1 : 0) {
                    answerPager
                } back: {
                    thoughtFace
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showingThought && hasOriginal {
                    OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                        showingOriginal.toggle()
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipShape(cardShape)
            .overlay {
                cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
            .contentShape(cardShape)

            dots
                .frame(height: 18)
                .opacity(!showingThought && results.count > 1 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if pagedStyle == nil {
                pagedStyle = results.first?.style
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showingThought ? "Shows the answers" : "Shows the original thought")
        .accessibilityAction(named: showingThought ? "Show answers" : "Show original thought") {
            flip()
        }
    }

    private var accessibilityLabel: String {
        if showingThought {
            return thought
        }

        guard let result = results[safe: activeIndex] else {
            return "Answers"
        }

        return "\(result.style.displayName) reframe. \(result.reframe)"
    }

    private var hasOriginal: Bool {
        guard let thoughtOriginal else {
            return false
        }

        return thoughtOriginal != thought
    }

    private var thoughtFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            InitialsAvatar(side: 32, fill: theme.ink, symbol: theme.paper)

            Text(showingOriginal ? (thoughtOriginal ?? thought) : thought)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: flip)
    }

    private var answerPager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(results, id: \.style) { result in
                    answerPage(result)
                        .containerRelativeFrame(.horizontal)
                        .id(result.style)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagedStyle)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .clipped()
    }

    private func answerPage(_ result: ReframeResult) -> some View {
        let appearance = CardStyleAppearance(style: result.style)

        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                stylePill(appearance)

                Text(result.reframe)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: flip)

            recookButton(for: result.style, ink: appearance.ink)
                .padding(.bottom, 12)
                .zIndex(1)
        }
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    private func recookButton(for style: Style, ink: Color) -> some View {
        let isRecooking = recookingStyle == style
        return Button {
            onRecook(style)
        } label: {
            HStack(spacing: 4) {
                if isRecooking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(ink)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text("New answer")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(ink.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(recookingStyle != nil)
        .opacity(recookingStyle == nil || isRecooking ? 1 : 0.45)
        .accessibilityLabel("New \(style.displayName) answer")
    }

    private var dots: some View {
        let indices = ReframePageDots.visibleIndices(count: results.count)
        return HStack(spacing: 5) {
            ForEach(indices, id: \.self) { index in
                let isActive = index == activeIndex
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func flip() {
        flipHaptic += 1

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isFlipped.toggle()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)) {
            isFlipped.toggle()
        }
    }
}

/// Only shown when the cleaned original is in another language than the card copy.
private struct OriginalToggle: View {
    let showingOriginal: Bool
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 11, weight: .semibold))
                Text(showingOriginal ? "English" : "Original")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ink.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingOriginal ? "Show the English version" : "Show the original wording")
    }
}

fileprivate func stylePill(_ appearance: CardStyleAppearance) -> some View {
    HStack(spacing: 6) {
        Image(systemName: appearance.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 12, weight: .semibold))

        Text(appearance.style.displayName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
    .foregroundStyle(appearance.ink)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .padding(.vertical, 5)
    .background(appearance.ink.opacity(0.14), in: Capsule())
    .accessibilityHidden(true)
}

enum ReframePageDots {
    static func visibleIndices(count: Int) -> [Int] {
        guard count > 1 else {
            return []
        }

        return Array(0..<count)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}

private struct FlipStack<Front: View, Back: View>: View, Animatable {
    var progress: CGFloat
    var front: Front
    var back: Back

    init(
        progress: CGFloat,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.progress = progress
        self.front = front()
        self.back = back()
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showingBack = progress > 0.5

        ZStack {
            front
                .compositingGroup()
                .opacity(showingBack ? 0 : 1)
                .allowsHitTesting(!showingBack)

            back
                .compositingGroup()
                .scaleEffect(x: -1, y: 1)
                .opacity(showingBack ? 1 : 0)
                .allowsHitTesting(showingBack)
        }
        .rotation3DEffect(
            .radians(Double(progress) * .pi),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .compositingGroup()
    }
}
