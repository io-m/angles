import Observation
import SwiftUI

/// Your page, pushed over the stack: the cards you wrote and the cards you saved.
struct ProfileView: View {
    let safeAreaInsets: EdgeInsets
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore? = nil
    var onInspire: () -> Void = {}
    var onLogOut: (() -> Void)? = nil
    var onDeleteAccount: (() async -> AccountDeletion)? = nil
    var canLoadFullAppContent = false
    var onOpenAuthor: (HomeCard) -> Void = { _ in }
    var onOpenFollowed: (FollowedPerson) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showSettings = false
    @State private var showFollowing = false
    /// A follow push opens People on Notifications. The icon opens Following.
    @State private var peopleStartsOnNotifications = false

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
        // Read the photo here so the header updates when the server copy arrives after sign-in.
        let _ = identityStore?.photo
        VStack(spacing: 0) {
            ProfileHeader(
                title: profileTitle,
                identityStore: identityStore,
                hasUnreadFollows: viewModel.unreadFollowCount > 0,
                onBack: dismiss.callAsFunction,
                onOpenFollowing: { showFollowing = true },
                onOpenSettings: { showSettings = true }
            )
            .padding(.top, safeAreaInsets.top + 10)

            ProfileTabs(selection: segment)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .accessibilityIdentifier("profile.segment")

            ScrollView {
                list(for: viewModel.profileSegment)
                    .padding(.bottom, max(safeAreaInsets.bottom, 12) + 20)
            }
            .id(viewModel.profileSegment)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            .refreshable {
                await viewModel.refreshList(viewModel.profileSegment)
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
        .task(id: canLoadFullAppContent) {
            guard canLoadFullAppContent else {
                return
            }
            await viewModel.loadLibraryIfNeeded()
            await viewModel.loadFollowNotifications()
        }
        .onAppear(perform: openFollowNotificationsIfAsked)
        .onChange(of: viewModel.wantsFollowNotifications) { _, _ in
            openFollowNotificationsIfAsked()
        }
        .modifier(
            AccountSheets(
                showSettings: $showSettings,
                showPeople: $showFollowing,
                peopleStartsOnNotifications: peopleStartsOnNotifications,
                viewModel: viewModel,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onLogOut: onLogOut,
                onDeleteAccount: onDeleteAccount,
                onOpenFollowed: onOpenFollowed
            )
        )
        .onChange(of: showFollowing) { _, showing in
            if !showing {
                peopleStartsOnNotifications = false
            }
        }
    }

    @ViewBuilder
    private func list(for segment: ProfileSegment) -> some View {
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
        actions.onOpenAuthor = { onOpenAuthor(card) }
        actions.onToggleFollow = { viewModel.toggleFollow(authorId) }
        actions.onReport = { viewModel.reportCard(card.id, reason: $0) }
        actions.onBlock = {
            viewModel.blockAuthor(authorId, initials: card.authorInitials, avatarPath: card.authorAvatarPath)
        }
        return actions
    }

    private func openFollowNotificationsIfAsked() {
        guard viewModel.consumeFollowNotificationsRequest() else {
            return
        }
        peopleStartsOnNotifications = true
        showFollowing = true
    }
}

private struct ProfileHeader: View {
    let title: String
    var identityStore: ProfileIdentityStore?
    var hasUnreadFollows: Bool
    let onBack: () -> Void
    let onOpenFollowing: () -> Void
    let onOpenSettings: () -> Void

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

            ProfileAvatar(
                identityStore: identityStore,
                letters: UserInitials.letters,
                side: 36,
                fill: theme.ink,
                symbol: theme.paper
            )
            .accessibilityHidden(true)

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button(action: onOpenFollowing) {
                CircleIcon(
                    systemName: "person.2",
                    fill: theme.surface,
                    symbol: theme.ink,
                    hairline: theme.cardHairline
                )
                .overlay(alignment: .topTrailing) {
                    if hasUnreadFollows {
                        Circle()
                            .fill(theme.ink)
                            .frame(width: 8, height: 8)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasUnreadFollows ? "People, new" : "People")

            Button(action: onOpenSettings) {
                CircleIcon(
                    systemName: "gearshape",
                    fill: theme.surface,
                    symbol: theme.ink,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(height: 52)
    }
}

/// Yours | Loved: icon and title, with an underline that slides to the open tab.
private struct ProfileTabs: View {
    @Binding var selection: ProfileSegment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var underline
    @State private var selectHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileSegment.allCases, id: \.self) { segment in
                tab(segment)
            }
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: selectHaptic)
    }

    private func tab(_ segment: ProfileSegment) -> some View {
        let selected = segment == selection
        return Button {
            guard segment != selection else {
                return
            }
            selectHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                selection = segment
            }
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: selected ? segment.selectedSymbol : segment.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? tint(for: segment) : theme.muted)
                    Text(segment.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? theme.ink : theme.muted)
                }
                .frame(height: 22)
                ZStack {
                    Color.clear
                        .frame(height: 2)
                    if selected {
                        Capsule()
                            .fill(tint(for: segment))
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func tint(for segment: ProfileSegment) -> Color {
        segment == .saved ? ActionColors.love : theme.ink
    }
}

private extension ProfileSegment {
    var symbol: String {
        switch self {
        case .yours: "square.stack"
        case .saved: "heart"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .yours: "square.stack.fill"
        case .saved: "heart.fill"
        }
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
    NavigationStack {
        ProfileView(
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            viewModel: HomeViewModel(),
            storeKitManager: StoreKitManager()
        )
    }
    .environmentObject(ThemeStore())
}
