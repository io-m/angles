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
                    onRemoveFromBoard: { onRemoveFromBoard(card) }
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
                    onRemoveFromBoard: { onRemoveFromBoard(card) }
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
}

/// A premium traveling border spark with a deepened ambient shadow that fades out while moving.
private struct CardArrivalGlow: View {
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: CGFloat = 0
    @State private var angle: Double = -90 // Start at top

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
                        color: tint.opacity((colorScheme == .dark ? 0.15 : 0.2) * level),
                        radius: 24,
                        x: 0,
                        y: 8
                    )
                    .shadow(
                        color: Color.black.opacity((colorScheme == .dark ? 0.2 : 0.1) * level),
                        radius: 16,
                        x: 0,
                        y: 6
                    )

                // 2. Long, varying-intensity traveling spark (Google-style)
                shape
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .clear, location: 0.25), // 75% length tail
                                .init(color: tint.opacity(colorScheme == .dark ? 0.1 : 0.3), location: 0.60),
                                .init(color: tint.opacity(colorScheme == .dark ? 0.4 : 0.8), location: 0.95),
                                .init(color: colorScheme == .dark ? tint.opacity(0.8) : .white, location: 1.0)
                            ],
                            center: .center,
                            angle: .degrees(angle)
                        ),
                        lineWidth: 1.5
                    )
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
                // Travel smoothly with linear easing so it doesn't jitter
                // Travels 1.25 laps over 2.5 seconds so it never stops while visible
                withAnimation(.linear(duration: 2.5)) {
                    angle = 360
                }
            }
            .task {
                // Wait for 1.5 seconds before starting the fade out
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else {
                    return
                }
                // Smooth fade out over 0.8s while it is STILL moving
                withAnimation(.easeOut(duration: 0.8)) {
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
