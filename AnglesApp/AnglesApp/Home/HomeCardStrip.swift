import SwiftUI

struct HomeCardStrip: View, Equatable {
    let cards: [HomeCard]
    /// Width of the page the strip sits on. Measured once at the app root, not per page.
    let pageWidth: CGFloat
    let presentation: ReframeCardPresentation
    let cardRowHeight: CGFloat
    var openingStyle: Style? = nil
    var menuRole: (HomeCard) -> ReframeCardMenuRole = { card in
        card.isOwner ? .owner : .savedFromFeed
    }
    var onDelete: (HomeCard) -> Void
    var onToggleFavorite: (HomeCard, Style) -> Void
    var onSetPublic: (HomeCard, Bool) -> Void
    var onRemoveFromBoard: (HomeCard) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    /// Lives here so scrolling a strip never redraws the page around it.
    @State private var scrollID: UUID?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    static func == (lhs: HomeCardStrip, rhs: HomeCardStrip) -> Bool {
        lhs.cards == rhs.cards
            && lhs.pageWidth == rhs.pageWidth
            && lhs.presentation == rhs.presentation
            && lhs.cardRowHeight == rhs.cardRowHeight
            && lhs.openingStyle == rhs.openingStyle
    }

    /// A concrete width, not `containerRelativeFrame`: nested in a strip that would
    /// resolve against the wrong container.
    private var cardWidth: CGFloat {
        min(pageWidth * 0.84, 340)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(cards) { card in
                        ReframeCardView(
                            card: card,
                            presentation: presentation,
                            menuRole: menuRole(card),
                            openingStyle: openingStyle,
                            onDelete: { onDelete(card) },
                            onToggleFavorite: { style in onToggleFavorite(card, style) },
                            onSetPublic: { isPublic in onSetPublic(card, isPublic) },
                            onRemoveFromBoard: { onRemoveFromBoard(card) }
                        )
                        .equatable()
                        .frame(width: cardWidth)
                        .id(card.id)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            )
                        )
                    }
                }
                .padding(.horizontal, 16)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(height: cardRowHeight)
            .onAppear {
                if scrollID == nil {
                    scrollID = cards.first?.id
                }
            }
            .onChange(of: cards.map(\.id)) { _, ids in
                if let scrollID, ids.contains(scrollID) {
                    return
                }
                scrollID = ids.first
            }

            if cards.count > 1 {
                stripPageDots
            }
        }
    }

    private var stripPageDots: some View {
        let activeID = scrollID ?? cards.first?.id
        return HStack(spacing: 5) {
            ForEach(cards) { card in
                let isActive = card.id == activeID
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
