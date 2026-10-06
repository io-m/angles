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
    var onReport: (HomeCard, ReportReason) -> Void = { _, _ in }
    var onBlock: (HomeCard) -> Void = { _ in }
    var onOpenAuthor: ((HomeCard) -> Void)? = nil
    var onToggleFollow: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0
    var offersOwnerPrivacyMenu = false

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.presentation == rhs.presentation
            && lhs.openingStyle == rhs.openingStyle
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
            && lhs.offersOwnerPrivacyMenu == rhs.offersOwnerPrivacyMenu
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
                    onReport: { reason in onReport(card, reason) },
                    onBlock: { onBlock(card) },
                    onOpenAuthor: openAuthorAction(for: card),
                    onToggleFollow: followAction(for: card),
                    offersOwnerPrivacyMenu: offersOwnerPrivacyMenu
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
    var onReport: (HomeCard, ReportReason) -> Void = { _, _ in }
    var onBlock: (HomeCard) -> Void = { _ in }
    var shiningCardID: UUID? = nil
    var onOpenAuthor: ((HomeCard) -> Void)? = nil
    var onToggleFollow: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0
    var offersOwnerPrivacyMenu = false
    /// A card reached the screen (or the lazy stack's short lead past it). Home's refresh
    /// uses this to tell cards the reader has passed from cards still below them.
    var onCardAppear: ((HomeCard) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: TallHomeCardGrid, rhs: TallHomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.cardMaxHeight == rhs.cardMaxHeight
            && lhs.rowSpacing == rhs.rowSpacing
            && lhs.openingStyle == rhs.openingStyle
            && lhs.shiningCardID == rhs.shiningCardID
            && lhs.loadMorePrefetchDistance == rhs.loadMorePrefetchDistance
            && lhs.offersOwnerPrivacyMenu == rhs.offersOwnerPrivacyMenu
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
                    onReport: { reason in onReport(card, reason) },
                    onBlock: { onBlock(card) },
                    onOpenAuthor: openAuthorAction(for: card),
                    onToggleFollow: followAction(for: card),
                    offersOwnerPrivacyMenu: offersOwnerPrivacyMenu
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
                    onCardAppear?(card)
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
}

/// A traveling border spark. Home uses the full lap and shadow; chat uses a quieter pass;
/// the refresh pill uses one fast lap around its capsule.
struct CardArrivalGlow<S: Shape>: View {
    enum Prominence {
        case home
        case subtle
        /// One quick lap on the pull-to-refresh pill. Thin stroke, little bloom.
        case pill
    }

    let tint: Color
    var prominence: Prominence = .home
    let shape: S

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: CGFloat = 0
    @State private var rotation: Double = -90 // Start at top

    private var strokeWidth: CGFloat {
        switch prominence {
        case .home: 2
        case .subtle: 1.25
        case .pill: 1.5
        }
    }

    private var lapDuration: Double {
        switch prominence {
        case .home: 2
        case .subtle: 1.6
        case .pill: 0.7
        }
    }

    private var fadeInDuration: Double {
        switch prominence {
        case .home: 0.4
        case .subtle: 0.3
        case .pill: 0.15
        }
    }

    private var holdBeforeFade: Duration {
        switch prominence {
        case .home: .milliseconds(1200)
        case .subtle: .milliseconds(900)
        case .pill: .milliseconds(650)
        }
    }

    private var fadeOutDuration: Double {
        switch prominence {
        case .home: 0.6
        case .subtle: 0.5
        case .pill: 0.3
        }
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            ZStack {
                arrivalShadow

                Color.clear
                    .overlay {
                        Rectangle()
                            .fill(
                                AngularGradient(
                                    stops: sparkStops,
                                    center: .center,
                                    angle: .degrees(0)
                                )
                            )
                            .frame(width: 1200, height: 1200)
                            .rotationEffect(.degrees(rotation))
                    }
                    .mask {
                        shape.stroke(lineWidth: strokeWidth)
                    }
                    .blendMode(.plusLighter)
                    .opacity(level)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.easeOut(duration: fadeInDuration)) {
                    level = 1
                }
                withAnimation(.linear(duration: lapDuration)) {
                    rotation = 360
                }
            }
            .task {
                try? await Task.sleep(for: holdBeforeFade)
                guard !Task.isCancelled else {
                    return
                }
                withAnimation(.easeOut(duration: fadeOutDuration)) {
                    level = 0
                }
            }
        }
    }

    private var arrivalShadow: some View {
        shape
            .fill(Color.clear)
            .shadow(
                color: tint.opacity(tintShadowOpacity * level),
                radius: shadowRadius.tint,
                x: 0,
                y: shadowOffset
            )
            .shadow(
                color: Color.black.opacity(blackShadowOpacity * level),
                radius: shadowRadius.black,
                x: 0,
                y: shadowOffset * 0.75
            )
    }

    private var shadowRadius: (tint: CGFloat, black: CGFloat) {
        switch prominence {
        case .home: (24, 16)
        case .subtle: (12, 8)
        case .pill: (6, 4)
        }
    }

    private var shadowOffset: CGFloat {
        switch prominence {
        case .home: 8
        case .subtle: 4
        case .pill: 1
        }
    }

    private var tintShadowOpacity: Double {
        let dark = colorScheme == .dark
        switch prominence {
        case .home:
            return dark ? 0.4 : 0.2
        case .subtle:
            return dark ? 0.18 : 0.1
        case .pill:
            return dark ? 0.14 : 0.08
        }
    }

    private var blackShadowOpacity: Double {
        let dark = colorScheme == .dark
        switch prominence {
        case .home:
            return dark ? 0.3 : 0.1
        case .subtle:
            return dark ? 0.12 : 0.04
        case .pill:
            return dark ? 0.08 : 0.03
        }
    }

    private var sparkStops: [Gradient.Stop] {
        let dark = colorScheme == .dark
        let scale: Double = prominence == .subtle ? 0.5 : 1
        let head: Color = dark
            ? tint.opacity(0.9 * scale)
            : (prominence == .subtle ? Color.white.opacity(0.5) : .white)
        return [
            .init(color: .clear, location: 0.0),
            .init(color: .clear, location: 0.50),
            .init(color: tint.opacity((dark ? 0.15 : 0.3) * scale), location: 0.75),
            .init(color: tint.opacity((dark ? 0.5 : 0.8) * scale), location: 0.95),
            .init(color: head, location: 0.99),
            .init(color: .clear, location: 1.0),
        ]
    }
}

extension CardArrivalGlow where S == RoundedRectangle {
    /// The card outline. Call sites that omit a shape keep this rounded rect.
    init(tint: Color, prominence: Prominence = .home) {
        self.init(
            tint: tint,
            prominence: prominence,
            shape: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
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
