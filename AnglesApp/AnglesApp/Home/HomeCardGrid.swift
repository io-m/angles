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
    var onOpenModel: ((HomeCard) -> Void)? = nil
    var onToggleFollow: (HomeCard) -> Void = { _ in }
    /// Fires before the end is visible, so a server-paged grid can append off screen.
    var onReachEnd: (() -> Void)? = nil
    var loadMorePrefetchDistance = 0
    var offersOwnerPrivacyMenu = false

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
                    onOpenModel: openModelAction(for: card),
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

/// A traveling border spark. Home uses the full lap and shadow; chat uses a quieter pass.
struct CardArrivalGlow: View {
    enum Prominence {
        case home
        case subtle
    }

    let tint: Color
    var prominence: Prominence = .home

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: CGFloat = 0
    @State private var rotation: Double = -90 // Start at top

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var isSubtle: Bool { prominence == .subtle }

    private var strokeWidth: CGFloat { isSubtle ? 1.25 : 2 }

    private var lapDuration: Double { isSubtle ? 1.6 : 2 }

    private var fadeInDuration: Double { isSubtle ? 0.3 : 0.4 }

    private var holdBeforeFade: Duration {
        .milliseconds(isSubtle ? 900 : 1200)
    }

    private var fadeOutDuration: Double { isSubtle ? 0.5 : 0.6 }

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
                radius: isSubtle ? 12 : 24,
                x: 0,
                y: isSubtle ? 4 : 8
            )
            .shadow(
                color: Color.black.opacity(blackShadowOpacity * level),
                radius: isSubtle ? 8 : 16,
                x: 0,
                y: isSubtle ? 3 : 6
            )
    }

    private var tintShadowOpacity: Double {
        let dark = colorScheme == .dark
        if isSubtle {
            return dark ? 0.18 : 0.1
        }
        return dark ? 0.4 : 0.2
    }

    private var blackShadowOpacity: Double {
        let dark = colorScheme == .dark
        if isSubtle {
            return dark ? 0.12 : 0.04
        }
        return dark ? 0.3 : 0.1
    }

    private var sparkStops: [Gradient.Stop] {
        let dark = colorScheme == .dark
        let scale: Double = isSubtle ? 0.5 : 1
        let head: Color = dark
            ? tint.opacity(0.9 * scale)
            : (isSubtle ? Color.white.opacity(0.5) : .white)
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
