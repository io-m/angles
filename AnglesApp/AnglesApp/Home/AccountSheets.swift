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

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSettings) {
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
            .sheet(isPresented: $showPeople) {
                FollowingSheet(
                    people: viewModel.followedPeople,
                    notices: viewModel.followNotices,
                    loadState: viewModel.followingLoadState,
                    noticesLoadState: viewModel.followNoticesLoadState,
                    startsOnNotifications: peopleStartsOnNotifications || viewModel.unreadFollowCount > 0,
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
                        showPeople = false
                        onOpenFollowed(person)
                    },
                    onOpenNotice: { notice in
                        showPeople = false
                        onOpenFollowed(
                            FollowedPerson(
                                id: notice.actorId,
                                initials: notice.initials,
                                avatarPath: notice.avatarPath
                            )
                        )
                    },
                    writeError: viewModel.writeError,
                    onDismissError: viewModel.dismissWriteError
                )
                .task {
                    async let following: Void = viewModel.loadFollowing()
                    async let notices: Void = viewModel.loadFollowNotifications()
                    _ = await (following, notices)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
            }
    }
}
