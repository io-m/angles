import SwiftUI

struct AuthorRoute: Hashable, Identifiable {
    let id: UUID
    let initials: String
    let avatarPath: String?
    let isSelf: Bool
}

struct AuthorProfileView: View {
    let route: AuthorRoute
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let onOpenAuthor: (HomeCard) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showBlockConfirm = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var header: AuthorHeader {
        viewModel.authorHeader(for: route.id)
            ?? AuthorHeader(
                initials: route.initials,
                avatarPath: route.avatarPath,
                isSelf: route.isSelf,
                following: false
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            AuthorChrome(
                header: header,
                onBack: dismiss.callAsFunction,
                onToggleFollow: { viewModel.toggleFollow(route.id) },
                onRequestBlock: { showBlockConfirm = true }
            )
            .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)
            .padding(.bottom, 8)

            ScrollView {
                AngleCardListContent(
                    list: viewModel.authorList(route.id),
                    loadingLabel: "Loading posts",
                    makeActions: actions,
                    onRetry: { viewModel.retryLoadAuthor(route.id) },
                    onLoadMore: { viewModel.loadMoreAuthor(route.id) },
                    onRetryLoadMore: { viewModel.retryLoadMoreAuthor(route.id) }
                ) {
                    CardListEmptyNote(text: header.isSelf ? "You haven't posted anything yet." : "No posts yet.")
                }
                .padding(.bottom, max(safeAreaInsets.bottom, 12) + 20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            .refreshable {
                await viewModel.refreshAuthor(route.id)
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(theme.grey.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .wideBackSwipe()
        .tint(theme.ink)
        .accessibilityAction(named: "Back") {
            dismiss()
        }
        .task(id: route.id) {
            await viewModel.loadAuthorIfNeeded(route)
        }
        .confirmationDialog(
            "Block \(displayInitials)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive, action: blockRouteAuthor)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their posts will disappear, and you won't be able to follow each other.")
        }
    }

    private func actions(for card: HomeCard, style: Style) -> AngleCardActions {
        var actions = AngleCardActions()
        if card.isOwner {
            actions.onDelete = { viewModel.deleteCard(card.id) }
            actions.onSetPublic = { viewModel.setPublic(card.id, isPublic: $0) }
            return actions
        }
        actions.onToggleSave = { viewModel.toggleSave(card.id, style: style) }
        guard let authorId = card.authorId else {
            return actions
        }
        actions.onToggleFollow = { viewModel.toggleFollow(authorId) }
        actions.onReport = { viewModel.reportCard(card.id, reason: $0) }
        actions.onBlock = {
            viewModel.blockAuthor(authorId, initials: card.authorInitials, avatarPath: card.authorAvatarPath)
        }
        return actions
    }

    private func blockRouteAuthor() {
        guard !header.isSelf else { return }
        viewModel.blockAuthor(
            route.id,
            initials: header.initials,
            avatarPath: header.avatarPath
        )
    }

    private var displayInitials: String {
        let trimmed = header.initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this person" : trimmed
    }
}

private struct AuthorChrome: View {
    let header: AuthorHeader
    let onBack: () -> Void
    let onToggleFollow: () -> Void
    let onRequestBlock: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onBack) {
                CircleIcon(
                    systemName: "chevron.left",
                    fill: theme.surface,
                    symbol: theme.ink,
                    weight: .semibold,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            ZStack(alignment: .bottomTrailing) {
                if header.isSelf {
                    authorMark
                } else {
                    Menu {
                        Button(role: .destructive, action: onRequestBlock) {
                            Label("Block", systemImage: "hand.raised")
                        }
                    } label: {
                        authorMark
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Author actions")
                    .accessibilityHint("Includes block")
                }

                if !header.isSelf {
                    FollowBadge(
                        following: header.following,
                        action: onToggleFollow
                    )
                    .offset(FollowBadge.overhang)
                }
            }
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(height: HeaderCollapse.headerHeight)
    }

    private var authorMark: some View {
        AuthorMark(
            initials: header.initials,
            avatarPath: header.avatarPath,
            prefersLocalPhoto: header.isSelf,
            side: CircleIcon.Size.normal.side,
            fill: theme.ink,
            symbol: theme.paper
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Posts by \(header.initials)")
        .accessibilityAddTraits(.isHeader)
    }
}
