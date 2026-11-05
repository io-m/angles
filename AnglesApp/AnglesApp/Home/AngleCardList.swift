import SwiftUI

/// One list card. It keeps its own angle, opening on the one it was saved on.
struct AngleCardListRow: View {
    let card: HomeCard
    let makeActions: (HomeCard, Style) -> AngleCardActions

    @State private var style: Style

    init(card: HomeCard, makeActions: @escaping (HomeCard, Style) -> AngleCardActions) {
        self.card = card
        self.makeActions = makeActions
        let opening = card.isSaved ? card.decision?.style : nil
        _style = State(initialValue: opening.flatMap { card.hasStyle($0) ? $0 : nil } ?? card.openingStyle)
    }

    var body: some View {
        AngleCardFace(card: card, sizing: .list, style: $style, actions: makeActions(card, style))
    }
}

/// Profile and author pages: a plain list of cards with load, error, empty, and paging states.
struct AngleCardListContent<Empty: View>: View {
    let list: CardList
    let loadingLabel: String
    let makeActions: (HomeCard, Style) -> AngleCardActions
    let onRetry: () -> Void
    let onLoadMore: () -> Void
    let onRetryLoadMore: () -> Void
    @ViewBuilder let empty: () -> Empty

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    /// Start the next page this many cards before the end.
    private static var prefetchDistance: Int { 4 }

    var body: some View {
        switch list.loadState {
        case .loading where list.cards.isEmpty:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .accessibilityLabel(loadingLabel)
        case .failed(let message) where list.cards.isEmpty:
            VStack(alignment: .leading, spacing: 12) {
                Text(message)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                Button("Retry", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
            }
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        default:
            if list.cards.isEmpty, list.footerState == .idle {
                empty()
            } else {
                LazyVStack(spacing: HeaderCollapse.horizontalPadding) {
                    ForEach(Array(list.cards.enumerated()), id: \.element.id) { index, card in
                        AngleCardListRow(card: card, makeActions: makeActions)
                            .onAppear {
                                if index >= list.cards.count - Self.prefetchDistance {
                                    onLoadMore()
                                }
                            }
                    }
                    footer
                }
                .padding(.horizontal, HeaderCollapse.horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch list.footerState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .accessibilityLabel("Loading more cards")
        case .failed:
            Button("Retry loading more", action: onRetryLoadMore)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }
}

/// A short line for an empty list.
struct CardListEmptyNote: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
