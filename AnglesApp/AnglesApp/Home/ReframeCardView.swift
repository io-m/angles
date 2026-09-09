import SwiftUI

struct ReframeCardView: View {
    let card: HomeCard
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 226
    @State private var pagedSlideID: UUID?
    @State private var showActions = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var showsPageDots: Bool {
        card.slides.count > 1
    }

    private var currentIndex: Int {
        if let pagedSlideID,
           let index = card.slides.firstIndex(where: { $0.id == pagedSlideID })
        {
            return index
        }

        return 0
    }

    private var visibleDotIndices: [Int] {
        let count = card.slides.count
        guard count > 1 else {
            return []
        }

        if count <= 3 {
            return Array(0..<count)
        }

        if currentIndex <= 1 {
            return [0, 1, 2]
        }

        if currentIndex >= count - 2 {
            return [count - 3, count - 2, count - 1]
        }

        return [currentIndex - 1, currentIndex, currentIndex + 1]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pager

            footer
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(cardShape)
        .overlay(alignment: .topLeading) {
            if let slide = currentSlide {
                stylePill(for: slide.result.style)
                    .padding(.leading, 14)
                    .padding(.top, 14)
            }
        }
        .overlay(alignment: .topTrailing) {
            menuButton
                .padding(.trailing, 10)
                .padding(.top, 10)
        }
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .onAppear {
            if pagedSlideID == nil {
                pagedSlideID = card.slides.first?.id
            }
        }
    }

    @ViewBuilder
    private var pager: some View {
        if card.slides.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(card.slides) { slide in
                        FlipReframeCard(
                            thought: slide.thought,
                            result: slide.result
                        )
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
            .clipped()
        } else if let slide = card.slides.first {
            FlipReframeCard(
                thought: slide.thought,
                result: slide.result
            )
        }
    }

    private var footer: some View {
        ZStack(alignment: .bottom) {
            pageDots
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

            HStack {
                Text(HomeViewModel.dateLabel(for: card.createdAt))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(height: 34, alignment: .bottom)
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(visibleDotIndices, id: \.self) { index in
                let isActive = index == currentIndex
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .frame(minHeight: 6)
        .animation(dotAnimation, value: currentIndex)
        .opacity(showsPageDots ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var dotAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.72)
    }

    private var currentSlide: HomeCardSlide? {
        if let pagedSlideID,
           let slide = card.slides.first(where: { $0.id == pagedSlideID })
        {
            return slide
        }

        return card.slides.first
    }

    private func stylePill(for style: Style) -> some View {
        let appearance = CardStyleAppearance(style: style)

        return HStack(spacing: 6) {
            Image(systemName: appearance.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))

            Text(style.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(appearance.ink)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(appearance.ink.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.displayName)
    }

    private var menuButton: some View {
        Button {
            showActions = true
        } label: {
            Image(systemName: "ellipsis.vertical")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .popover(isPresented: $showActions) {
            cardActions
                .presentationCompactAdaptation(.popover)
        }
    }

    private var cardActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showActions = false
                onEdit()
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                showActions = false
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minWidth: 180)
    }
}

private struct FlipReframeCard: View {
    let thought: String
    let result: ReframeResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFlipped = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var styleAppearance: CardStyleAppearance {
        CardStyleAppearance(style: result.style)
    }

    var body: some View {
        Button(action: flip) {
            FlipStack(progress: isFlipped ? 1 : 0) {
                frontFace
            } back: {
                backFace
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .compositingGroup()
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(CardFlipButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isFlipped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isFlipped
                ? "\(result.style.displayName) reframe. \(result.reframe)"
                : "\(result.style.displayName). \(thought)"
        )
        .accessibilityHint(isFlipped ? "Shows the original thought" : "Shows the reframe")
    }

    private var frontFace: some View {
        cardFace(background: frontSurface) {
            faceContent(
                text: thought,
                textFont: .body.weight(.semibold)
            )
        }
    }

    private var backFace: some View {
        cardFace(background: backSurface) {
            faceContent(
                text: result.reframe,
                textFont: .callout.weight(.medium)
            )
        }
    }

    private func faceContent(text: String, textFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(textFont)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .padding(.bottom, 22)
    }

    private var frontSurface: Color {
        theme.surface
    }

    private var backSurface: some View {
        styleAppearance.washFill(over: theme.surface)
    }

    private func cardFace<Background: View, Content: View>(
        background: Background,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { background }
    }

    private func flip() {
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

private struct CardFlipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
        let isMidFlip = progress > 0.02 && progress < 0.98

        Group {
            if isMidFlip {
                ZStack {
                    front
                        .compositingGroup()
                        .opacity(showingBack ? 0 : 1)

                    back
                        .compositingGroup()
                        .scaleEffect(x: -1, y: 1)
                        .opacity(showingBack ? 1 : 0)
                }
                .rotation3DEffect(
                    .radians(Double(progress) * .pi),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .compositingGroup()
            } else if showingBack {
                back
            } else {
                front
            }
        }
    }
}
