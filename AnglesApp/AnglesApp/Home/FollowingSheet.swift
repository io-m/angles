import SwiftUI

/// Who you follow, and who followed you or loved your posts, on two tabs. Same sheet
/// chrome as Settings.
struct FollowingSheet: View {
    /// One row of Notifications: a follow or a love, newest first.
    private enum NoticeRow: Identifiable {
        case follow(FollowNotice)
        case love(LoveNotice)

        var id: UUID {
            switch self {
            case .follow(let notice): notice.id
            case .love(let notice): notice.id
            }
        }

        var createdAt: Date {
            switch self {
            case .follow(let notice): notice.createdAt
            case .love(let notice): notice.createdAt
            }
        }
    }

    private enum PeopleTab: String, CaseIterable, Hashable {
        case following
        case notifications

        var title: String {
            switch self {
            case .following: "Following"
            case .notifications: "Notifications"
            }
        }

        var symbol: String {
            switch self {
            case .following: "person.2"
            case .notifications: "bell"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .following: "person.2.fill"
            case .notifications: "bell.fill"
            }
        }
    }

    let people: [FollowedPerson]
    let notices: [FollowNotice]
    let loves: [LoveNotice]
    let loadState: LibraryLoadState
    let noticesLoadState: LibraryLoadState
    /// A follow push opens Notifications. The people icon opens Following.
    var startsOnNotifications = false
    var onRetry: () -> Void
    /// Marks the follow rows read. Called when Notifications is the tab on screen.
    var onViewNotifications: () -> Void = {}
    var onUnfollow: (FollowedPerson) -> Void
    var onFollowBack: (FollowNotice) -> Void
    var onOpen: (FollowedPerson) -> Void
    var onOpenNotice: (FollowNotice) -> Void
    /// Follow someone who loved a post. Only a lover who shows their name has a row to follow.
    var onFollowLover: (LoveNotice.Actor) -> Void
    var onOpenLover: (LoveNotice.Actor) -> Void
    /// A failed unfollow puts the row back; this says why.
    var writeError: String? = nil
    var onDismissError: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var tab: PeopleTab

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    init(
        people: [FollowedPerson],
        notices: [FollowNotice],
        loves: [LoveNotice] = [],
        loadState: LibraryLoadState,
        noticesLoadState: LibraryLoadState,
        startsOnNotifications: Bool = false,
        onRetry: @escaping () -> Void,
        onViewNotifications: @escaping () -> Void = {},
        onUnfollow: @escaping (FollowedPerson) -> Void,
        onFollowBack: @escaping (FollowNotice) -> Void,
        onOpen: @escaping (FollowedPerson) -> Void,
        onOpenNotice: @escaping (FollowNotice) -> Void,
        onFollowLover: @escaping (LoveNotice.Actor) -> Void = { _ in },
        onOpenLover: @escaping (LoveNotice.Actor) -> Void = { _ in },
        writeError: String? = nil,
        onDismissError: @escaping () -> Void = {}
    ) {
        self.people = people
        self.notices = notices
        self.loves = loves
        self.onFollowLover = onFollowLover
        self.onOpenLover = onOpenLover
        self.loadState = loadState
        self.noticesLoadState = noticesLoadState
        self.startsOnNotifications = startsOnNotifications
        self.onRetry = onRetry
        self.onViewNotifications = onViewNotifications
        self.onUnfollow = onUnfollow
        self.onFollowBack = onFollowBack
        self.onOpen = onOpen
        self.onOpenNotice = onOpenNotice
        self.writeError = writeError
        self.onDismissError = onDismissError
        _tab = State(initialValue: startsOnNotifications ? .notifications : .following)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var needle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPeople: [FollowedPerson] {
        guard !needle.isEmpty else {
            return people
        }
        return people.filter {
            displayInitials($0.initials).localizedStandardContains(needle)
        }
    }

    private var filteredRows: [NoticeRow] {
        let follows = notices
            .filter {
                needle.isEmpty
                    || $0.publicLabel.localizedStandardContains(needle)
                    || $0.initials.localizedStandardContains(needle)
            }
            .map(NoticeRow.follow)
        let loved = loves
            .filter {
                needle.isEmpty
                    || $0.publicLabel.localizedStandardContains(needle)
                    || $0.thought.localizedStandardContains(needle)
            }
            .map(NoticeRow.love)
        return (follows + loved).sorted { $0.createdAt > $1.createdAt }
    }

    private var unreadCount: Int {
        notices.filter { $0.readAt == nil }.count + loves.filter { $0.readAt == nil }.count
    }

    var body: some View {
        PagingSplit(
            ids: Array(PeopleTab.allCases),
            selection: $tab,
            tint: { _ in theme.ink },
            label: { item, isSelected in
                tabLabel(item, isSelected: isSelected)
            },
            page: { item in
                tabBody(item)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
            }
        ) { bar, pages in
            ModalScreen(
                title: "People",
                searchText: $query,
                scrolls: false,
                header: AnyView(bar)
            ) {
                pages
            }
        }
        .onChange(of: tab) { _, item in
            guard item == .notifications else { return }
            onViewNotifications()
        }
        .task {
            guard tab == .notifications else { return }
            onViewNotifications()
        }
        .overlay {
            WriteErrorBanner(message: writeError, onDismiss: onDismissError)
                .padding(.top, 8)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86),
                    value: writeError
                )
        }
    }

    private var searching: Bool {
        !needle.isEmpty
    }

    private func tabLabel(_ item: PeopleTab, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            PagingTabLabel(
                title: item.title,
                symbol: item.symbol,
                selectedSymbol: item.selectedSymbol,
                isSelected: isSelected,
                tint: theme.ink
            )
            if item == .notifications, unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.paper)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, 4)
                    .background(theme.ink, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            item == .notifications && unreadCount > 0
                ? "Notifications, \(unreadCount) unread"
                : item.title
        )
    }

    @ViewBuilder
    private func tabBody(_ item: PeopleTab) -> some View {
        switch item {
        case .following:
            if searching && filteredPeople.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
            } else if people.isEmpty {
                status(loadState, empty: "You aren't following anyone yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredPeople.enumerated()), id: \.element.id) { index, person in
                        personRow(person, showsDivider: index < filteredPeople.count - 1)
                    }
                }
            }
        case .notifications:
            let rows = filteredRows
            if searching && rows.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
            } else if notices.isEmpty && loves.isEmpty {
                status(noticesLoadState, empty: "No follows or loves yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        switch row {
                        case .follow(let notice):
                            noticeRow(notice, showsDivider: index < rows.count - 1)
                        case .love(let notice):
                            loveRow(notice, showsDivider: index < rows.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func status(_ state: LibraryLoadState, empty: String) -> some View {
        VStack(spacing: 12) {
            switch state {
            case .loading:
                ProgressView()
                    .tint(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 88)
            case .failed(let message):
                Text(message)
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                Button("Try again", action: onRetry)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
            case .loaded:
                Text(empty)
                    .font(.body)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func personRow(_ person: FollowedPerson, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    onOpen(person)
                } label: {
                    HStack(spacing: 14) {
                        AuthorMark(
                            initials: person.initials,
                            avatarPath: person.avatarPath,
                            side: 40,
                            fill: theme.ink,
                            symbol: theme.paper
                        )

                        Text(displayInitials(person.initials))
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)

                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(displayInitials(person.initials))
                .accessibilityHint("Opens their posts")

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onUnfollow(person)
                } label: {
                    Image(systemName: "person.badge.minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unfollow \(displayInitials(person.initials))")
            }
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
    }

    private func noticeRow(_ notice: FollowNotice, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    onOpenNotice(notice)
                } label: {
                    HStack(spacing: 14) {
                        AuthorMark(
                            initials: notice.initials,
                            avatarPath: notice.avatarPath,
                            side: 40,
                            fill: theme.ink,
                            symbol: theme.paper
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(notice.publicLabel)
                                .font(.body.weight(.medium))
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                            Text("\(notice.sentence) · \(Self.relative.localizedString(for: notice.createdAt, relativeTo: Date()))")
                                .font(.subheadline)
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(notice.publicLabel) \(notice.sentence)")
                .accessibilityHint("Opens their posts")

                if notice.following {
                    Text("Following")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onFollowBack(notice)
                    } label: {
                        Text("Follow back")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Follow back \(notice.publicLabel)")
                }
            }
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
    }

    private func loveRow(_ notice: LoveNotice, showsDivider: Bool) -> some View {
        let when = Self.relative.localizedString(for: notice.createdAt, relativeTo: Date())
        let sentence = "Loved your \(notice.style.displayName) angle"
        let summary = HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if let actor = notice.actor {
                    AuthorMark(
                        initials: actor.initials,
                        avatarPath: actor.avatarPath,
                        side: 40,
                        fill: theme.ink,
                        symbol: theme.paper
                    )
                } else {
                    Circle()
                        .fill(theme.line)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(theme.muted)
                        }
                }
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(ActionColors.love, in: Circle())
                    .overlay(Circle().stroke(theme.grey, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.publicLabel)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text("\(sentence) · \(when)")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                Text("“\(notice.thought)”")
                    .font(.subheadline)
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
                    .padding(.top, 2)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let actor = notice.actor {
                    Button {
                        onOpenLover(actor)
                    } label: {
                        summary
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(notice.publicLabel) loved your post, \(notice.style.displayName) angle, \(when)")
                    .accessibilityHint("Opens their posts")

                    if !actor.following {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onFollowLover(actor)
                        } label: {
                            Text("Follow")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.ink)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Follow \(notice.publicLabel)")
                    }
                } else {
                    summary
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Someone loved your post, \(notice.style.displayName) angle, \(when)")
                }
            }
            .padding(.vertical, 12)

            if showsDivider {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
    }

    private func displayInitials(_ initials: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Y" : trimmed
    }
}
