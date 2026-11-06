import SwiftUI

/// Settings and People (Following and Notifications), the same two sheets from the stack's
/// header and from Profile.
struct AccountSheets: ViewModifier {
    @Binding var showSettings: Bool
    @Binding var showPeople: Bool
    /// A follow push or the bell opens People on Notifications. Profile's icon opens Following
    /// unless something is unread.
    var peopleStartsOnNotifications: Bool
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?
    var onLogOut: (() -> Void)?
    var onDeleteAccount: (() async -> AccountDeletion)?
    var onOpenFollowed: (FollowedPerson) -> Void
    var onOpenPost: (PostRoute) -> Void = { _ in }
    var onSheetDismissed: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore
    /// Opening a person or post waits until People has closed, so the next sheet is not presented on top of it.
    @State private var pendingFollowed: FollowedPerson?
    @State private var pendingPost: PostRoute?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSettings, onDismiss: onSheetDismissed) {
                SettingsView(
                    storeKitManager: storeKitManager,
                    identityStore: identityStore,
                    onLogOut: {
                        onLogOut?()
                        showSettings = false
                    },
                    onDeleteAccount: {
                        let result = await onDeleteAccount?() ?? .failed
                        if result == .deleted {
                            showSettings = false
                        }
                        return result
                    },
                    blockedPeople: viewModel.blockedPeople,
                    blocksLoadState: viewModel.blocksLoadState,
                    onLoadBlocks: { await viewModel.loadBlocks() },
                    onRetryBlocks: { Task { await viewModel.loadBlocks() } },
                    onUnblock: viewModel.unblock,
                    writeError: viewModel.writeError,
                    onDismissWriteError: viewModel.dismissWriteError
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
            }
            .sheet(isPresented: $showPeople, onDismiss: {
                if let post = pendingPost {
                    pendingPost = nil
                    onOpenPost(post)
                    return
                }
                if let person = pendingFollowed {
                    pendingFollowed = nil
                    onOpenFollowed(person)
                    return
                }
                onSheetDismissed()
            }) {
                let startsOnNotifications = peopleStartsOnNotifications || viewModel.unreadNotificationCount > 0
                FollowingSheet(
                    people: viewModel.followedPeople,
                    notices: viewModel.followNotices,
                    loves: viewModel.loveNotices,
                    loadState: viewModel.followingLoadState,
                    noticesLoadState: viewModel.followNoticesLoadState,
                    startsOnNotifications: startsOnNotifications,
                    onRetry: {
                        Task {
                            await viewModel.loadFollowing()
                            await viewModel.loadFollowNotifications()
                        }
                    },
                    onViewNotifications: { viewModel.openedFollowNotifications() },
                    onUnfollow: { person in
                        viewModel.unfollow(person)
                    },
                    onFollowBack: { notice in
                        viewModel.followBack(notice.actorId)
                    },
                    onOpen: { person in
                        pendingFollowed = person
                        showPeople = false
                    },
                    onOpenNotice: { notice in
                        viewModel.markPushNotificationRead(followId: notice.id)
                        pendingFollowed = FollowedPerson(
                            id: notice.actorId,
                            initials: notice.initials,
                            avatarPath: notice.avatarPath
                        )
                        showPeople = false
                    },
                    onFollowLover: { actor in
                        viewModel.followBack(actor.id)
                    },
                    onOpenLove: { notice in
                        viewModel.markPushNotificationRead(loveId: notice.id, cardId: notice.cardId)
                        pendingPost = PostRoute(id: notice.cardId, initialStyle: notice.style)
                        showPeople = false
                    },
                    writeError: viewModel.writeError,
                    onDismissError: viewModel.dismissWriteError
                )
                .task {
                    await viewModel.loadFollowing()
                    if !startsOnNotifications {
                        await viewModel.loadFollowNotifications()
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
            }
    }
}
