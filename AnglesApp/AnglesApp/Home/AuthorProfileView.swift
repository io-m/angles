import SwiftUI

struct AuthorRoute: Hashable, Identifiable {
    let id: UUID
    let initials: String
    let avatarPath: String?
    let isSelf: Bool
}

struct AuthorProfileView: View {
    let route: AuthorRoute
    let viewModel: HomeViewModel

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
        ModalScreen(
            title: pageTitle,
            leading: unfollowAction,
            trailing: followAction
        ) {
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
            .padding(.bottom, 24)
        }
        .task(id: route.id) {
            await viewModel.loadAuthorIfNeeded(route)
        }
    }

    private var pageTitle: String {
        let trimmed = header.initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Posts" : trimmed
    }

    /// Unfollow sits on the left once you follow them. Follow sits on the right until then.
    private var unfollowAction: ModalAction? {
        guard !header.isSelf, header.following else { return nil }
        return ModalAction(title: "Unfollow", role: .destructive) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.toggleFollow(route.id)
        }
    }

    private var followAction: ModalAction? {
        guard !header.isSelf, !header.following else { return nil }
        return ModalAction(title: "Follow", role: .emphasis) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.toggleFollow(route.id)
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
}
