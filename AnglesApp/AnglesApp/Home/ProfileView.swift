import SwiftUI

/// Your page, a sheet over the stack: the cards you wrote and the cards you saved.
struct ProfileView: View {
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore? = nil
    var onInspire: () -> Void = {}
    var onLogOut: (() -> Void)? = nil
    var onDeleteAccount: (() async -> AccountDeletion)? = nil
    var canLoadFullAppContent = false
    /// An author sheet on top of this one is not Home, so a rating prompt waits.
    var onAuthorVisibility: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var authorRoute: AuthorRoute?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var profileTitle: String {
        identityStore?.profileTitle ?? "On this iPhone"
    }

    private var segment: Binding<ProfileSegment> {
        Binding(
            get: { viewModel.profileSegment },
            set: { viewModel.profileSegment = $0 }
        )
    }

    var body: some View {
        let _ = RenderCounter.hit("ProfileView")
        PagingSplit(
            ids: Array(ProfileSegment.allCases),
            selection: segment,
            tint: tabTint,
            label: { item, isSelected in
                PagingTabLabel(
                    title: item.title,
                    symbol: item.symbol,
                    selectedSymbol: item.selectedSymbol,
                    isSelected: isSelected,
                    tint: tabTint(item)
                )
            },
            page: { item in
                ProfilePage(
                    segment: item,
                    viewModel: viewModel,
                    onInspire: onInspire,
                    onOpenAuthor: { authorRoute = $0 }
                )
            }
        ) { bar, pages in
            ModalScreen(title: profileTitle, scrolls: false, header: AnyView(bar)) {
                pages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("profile.segment")
            }
        }
        .task(id: canLoadFullAppContent) {
            guard canLoadFullAppContent else {
                return
            }
            await viewModel.loadLibraryIfNeeded()
            await viewModel.loadFollowNotifications()
        }
        .sheet(item: $authorRoute) { route in
            AuthorProfileView(route: route, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationContentInteraction(.scrolls)
                .modifier(UserAppearance(store: themeStore))
        }
        .onChange(of: authorRoute?.id) { _, id in
            onAuthorVisibility(id != nil)
        }
    }

    private func tabTint(_ segment: ProfileSegment) -> Color {
        segment == .saved ? ActionColors.love : theme.ink
    }
}

/// One profile list. It reads the view model itself, so a saved card updates this page.
private struct ProfilePage: View {
    let segment: ProfileSegment
    let viewModel: HomeViewModel
    var onInspire: () -> Void
    var onOpenAuthor: (AuthorRoute) -> Void

    var body: some View {
        AngleCardListContent(
            list: viewModel.list(segment),
            loadingLabel: segment == .yours ? "Loading your cards" : "Loading loved cards",
            makeActions: actions,
            onRetry: { viewModel.retryList(segment) },
            onLoadMore: { viewModel.loadMore(segment) },
            onRetryLoadMore: { viewModel.retryLoadMore(segment) }
        ) {
            switch segment {
            case .yours:
                ProfileEmptyLibraryHero(onInspire: onInspire)
            case .saved:
                CardListEmptyNote(text: "Swipe right on a card, or tap the heart, to keep it here.")
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func actions(for card: HomeCard, style: Style) -> AngleCardActions {
        var actions = AngleCardActions()
        if card.isOwner {
            actions.onDelete = {
                withAnimation(.easeInOut(duration: 0.22)) {
                    viewModel.deleteCard(card.id)
                }
            }
            actions.onSetPublic = { viewModel.setPublic(card.id, isPublic: $0) }
            return actions
        }
        actions.onToggleSave = {
            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.toggleSave(card.id, style: style)
            }
        }
        guard !card.isHouse, let authorId = card.authorId else {
            return actions
        }
        actions.onOpenAuthor = {
            onOpenAuthor(
                AuthorRoute(
                    id: authorId,
                    initials: card.authorInitials,
                    avatarPath: card.authorAvatarPath,
                    isSelf: false
                )
            )
        }
        actions.onToggleFollow = { viewModel.toggleFollow(authorId) }
        actions.onReport = { viewModel.reportCard(card.id, reason: $0) }
        actions.onBlock = {
            viewModel.blockAuthor(authorId, initials: card.authorInitials, avatarPath: card.authorAvatarPath)
        }
        return actions
    }
}

private struct ProfileEmptyLibraryHero: View {
    var onInspire: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspireMarkCircle(
                fill: theme.paper,
                markSize: .big,
                hairline: theme.cardHairline
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Your library is empty")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Write what's stuck. We'll turn it into four angles.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onInspire) {
                HStack(spacing: 8) {
                    InspireMark(size: 18, rendering: .monochrome(theme.paper))
                    Text("Inspire me")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspire me")
            .accessibilityHint("Opens the composer to write your first thought")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Profile") {
    ProfileView(
        viewModel: HomeViewModel(),
        storeKitManager: StoreKitManager()
    )
    .environmentObject(ThemeStore())
}
