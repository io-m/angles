import SwiftUI

struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    var rowSpacing: CGFloat = HeaderCollapse.horizontalPadding
    var presentation: ReframeCardPresentation = .library
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .savedFromFeed
    }
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    var onOpenAuthor: ((HomeCard) -> Void)? = nil
    var onToggleFollow: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.presentation == rhs.presentation
            && lhs.openingStyle == rhs.openingStyle
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
    }

    var body: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    presentation: presentation,
                    menuRole: menuRole(card),
                    openingStyle: openingStyleFor(card),
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { style in onToggleFavorite(card, style) },
                    onSetPublic: { isPublic in onSetPublic(card, isPublic) },
                    onRemoveFromBoard: { onRemoveFromBoard(card) },
                    onOpenAuthor: openAuthorAction(for: card),
                    onToggleFollow: followAction(for: card)
                )
                .equatable()
                .onAppear {
                    guard let onReachEnd, card.id == loadMoreTriggerID else {
                        return
                    }
                    onReachEnd()
                }
            }
        }
    }

    private var loadMoreTriggerID: UUID? {
        guard !cards.isEmpty else {
            return nil
        }
        let configuredDistance = max(0, loadMorePrefetchDistance)
        let adaptiveDistance = min(configuredDistance, max(1, cards.count / 4))
        let distance = min(adaptiveDistance, cards.count - 1)
        return cards[cards.count - 1 - distance].id
    }

    private func openAuthorAction(for card: HomeCard) -> (() -> Void)? {
        guard card.authorId != nil, let onOpenAuthor else {
            return nil
        }
        return { onOpenAuthor(card) }
    }

    private func followAction(for card: HomeCard) -> (() -> Void)? {
        guard !card.isOwner, card.authorId != nil else {
            return nil
        }
        return { onToggleFollow(card) }
    }

    /// `ForEach` keys on `card.id` alone. An explicit identity that folded in favorite state
    /// rebuilt the card on every heart, which reset its selected style.
    private func openingStyleFor(_ card: HomeCard) -> Style? {
        switch presentation {
        case .favoriteAngles:
            return card.latestFavoriteStyle
        case .library, .tallLibrary:
            return openingStyle
        }
    }
}

/// Experiment (tall Home cards): one card per row, sized to its text.
/// Neighbors scale down slightly as they leave the viewport.
struct TallHomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    /// Viewport cap. Cards stay shorter than this; the reply scrolls if they would pass it.
    var cardMaxHeight: CGFloat = 520
    var rowSpacing: CGFloat = HeaderCollapse.horizontalPadding
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .feed
    }
    var onDelete: (HomeCard) -> Void = { _ in }
    var onToggleFavorite: (HomeCard, Style) -> Void = { _, _ in }
    var onSetPublic: (HomeCard, Bool) -> Void = { _, _ in }
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }
    var shiningCardID: UUID? = nil
    var onOpenAuthor: ((HomeCard) -> Void)? = nil
    var onOpenModel: ((HomeCard) -> Void)? = nil
    var onToggleFollow: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: TallHomeCardGrid, rhs: TallHomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.cardMaxHeight == rhs.cardMaxHeight
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.openingStyle == rhs.openingStyle
            && lhs.shiningCardID == rhs.shiningCardID
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
    }

    var body: some View {
        LazyVStack(spacing: rowSpacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    presentation: .tallLibrary,
                    menuRole: menuRole(card),
                    openingStyle: openingStyle,
                    tallCardMaxHeight: cardMaxHeight,
                    onDelete: { onDelete(card) },
                    onToggleFavorite: { style in onToggleFavorite(card, style) },
                    onSetPublic: { isPublic in onSetPublic(card, isPublic) },
                    onRemoveFromBoard: { onRemoveFromBoard(card) },
                    onOpenAuthor: openAuthorAction(for: card),
                    onOpenModel: openModelAction(for: card),
                    onToggleFollow: followAction(for: card)
                )
                .equatable()
                .overlay {
                    if card.id == shiningCardID, !reduceMotion {
                        CardArrivalGlow(
                            tint: CardStyleAppearance(
                                style: openingStyle ?? card.spotlightStyle
                            ).ink
                        )
                    }
                }
                .modifier(TallCardFocusTransition(enabled: !reduceMotion))
                .onAppear {
                    guard let onReachEnd, card.id == loadMoreTriggerID else {
                        return
                    }
                    onReachEnd()
                }
            }
        }
    }

    private var loadMoreTriggerID: UUID? {
        guard !cards.isEmpty else {
            return nil
        }
        let configuredDistance = max(0, loadMorePrefetchDistance)
        let adaptiveDistance = min(configuredDistance, max(1, cards.count / 4))
        let distance = min(adaptiveDistance, cards.count - 1)
        return cards[cards.count - 1 - distance].id
    }

    private func openAuthorAction(for card: HomeCard) -> (() -> Void)? {
        guard card.authorId != nil, let onOpenAuthor else {
            return nil
        }
        return { onOpenAuthor(card) }
    }

    private func openModelAction(for card: HomeCard) -> (() -> Void)? {
        guard card.model != nil, let onOpenModel else {
            return nil
        }
        return { onOpenModel(card) }
    }

    private func followAction(for card: HomeCard) -> (() -> Void)? {
        guard !card.isOwner, card.authorId != nil else {
            return nil
        }
        return { onToggleFollow(card) }
    }
}

/// A premium, Google-style smooth traveling border spark with a deepened ambient shadow.
private struct CardArrivalGlow: View {
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: CGFloat = 0
    @State private var rotation: Double = -90 // Start at top

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            ZStack {
                // 1. Increased card shadow (deep and soft)
                shape
                    .fill(Color.clear)
                    .shadow(
                        color: tint.opacity((colorScheme == .dark ? 0.4 : 0.2) * level),
                        radius: 24,
                        x: 0,
                        y: 8
                    )
                    .shadow(
                        color: Color.black.opacity((colorScheme == .dark ? 0.3 : 0.1) * level),
                        radius: 16,
                        x: 0,
                        y: 6
                    )

                // 2. Smooth, jitter-free traveling spark using a rotating masked layer
                Color.clear
                    .overlay {
                        Rectangle()
                            .fill(
                                AngularGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.50), // Long clear area
                                        .init(color: tint.opacity(colorScheme == .dark ? 0.15 : 0.3), location: 0.75), // Soft tail start
                                        .init(color: tint.opacity(colorScheme == .dark ? 0.5 : 0.8), location: 0.95), // Strong body
                                        .init(color: colorScheme == .dark ? tint.opacity(0.9) : .white, location: 0.99), // Bright head
                                        .init(color: .clear, location: 1.0) // Sharp cutoff
                                    ],
                                    center: .center,
                                    angle: .degrees(0) // Static gradient, we rotate the view instead
                                )
                            )
                            .frame(width: 1200, height: 1200) // Much larger to ensure it covers the card during rotation
                            .rotationEffect(.degrees(rotation))
                    }
                    .mask {
                        // The mask takes the size of Color.clear (the card's size), not the 1200x1200 overlay
                        shape.stroke(lineWidth: 2.0)
                    }
                    .blendMode(.plusLighter)
                    .opacity(level)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                // Fade in the shadow and spark
                withAnimation(.easeOut(duration: 0.4)) {
                    level = 1
                }
                // Hardware-accelerated rotation for perfect smoothness
                // Travels 1 lap (360 degrees) over 2.0 seconds
                withAnimation(.linear(duration: 2.0)) {
                    rotation = 360
                }
            }
            .task {
                // Wait for 1.2 seconds before starting the fade out
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else {
                    return
                }
                // Smooth fade out over 0.6s while it is STILL moving
                withAnimation(.easeOut(duration: 0.6)) {
                    level = 0
                }
            }
        }
    }
}

/// Focus effect: the settled card is full size; neighbors scale down as they travel in.
private struct TallCardFocusTransition: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.scrollTransition(.interactive, axis: .vertical) { effect, phase in
                let distance = CGFloat(min(1, abs(phase.value)))
                return effect.scaleEffect(1 - (0.04 * distance))
            }
        } else {
            content
        }
    }
}
