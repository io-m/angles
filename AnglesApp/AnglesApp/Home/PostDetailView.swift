import SwiftUI

struct PostRoute: Hashable, Identifiable {
    let id: UUID
    var initialStyle: Style? = nil
}

/// One post on its own screen, opened from a love notification in the bell list or a push.
/// The top-left X closes straight back to the Home stack.
struct PostDetailView: View {
    let route: PostRoute
    let viewModel: HomeViewModel
    var onClose: () -> Void
    var onOpenLover: (FollowedPerson) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme

    @State private var style: Style
    @State private var loadState: LibraryLoadState = .loading
    @State private var loadedCard: HomeCard?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    init(
        route: PostRoute,
        viewModel: HomeViewModel,
        onClose: @escaping () -> Void,
        onOpenLover: @escaping (FollowedPerson) -> Void = { _ in }
    ) {
        self.route = route
        self.viewModel = viewModel
        self.onClose = onClose
        self.onOpenLover = onOpenLover
        let existing = viewModel.postCard(id: route.id)
        let preferred = route.initialStyle.flatMap { candidate in
            existing?.hasStyle(candidate) == false ? nil : candidate
        }
        _style = State(initialValue: preferred ?? existing?.openingStyle ?? .stoic)
        _loadedCard = State(initialValue: existing)
        _loadState = State(initialValue: existing == nil ? .loading : .loaded)
    }

    private var currentCard: HomeCard? {
        viewModel.postCard(id: route.id) ?? loadedCard
    }

    private var cardLoves: [LoveNotice] {
        viewModel.loveNotices.filter { $0.cardId == route.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cardSection
                    if !cardLoves.isEmpty {
                        loversSection
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.grey.ignoresSafeArea())
        .tint(theme.ink)
        .presentationBackground(theme.grey)
        .presentationDragIndicator(.visible)
        .task(id: route.id) {
            await loadPost()
        }
    }

    private var topBar: some View {
        ZStack {
            Text("Post")
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                Button(action: onClose) {
                    CircleIcon(
                        systemName: "xmark",
                        fill: theme.surface,
                        symbol: theme.ink,
                        weight: .semibold,
                        hairline: theme.cardHairline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("post.close")

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var cardSection: some View {
        if let card = currentCard {
            AngleCardFace(
                card: card,
                sizing: .list,
                style: $style,
                actions: actions(for: card)
            )
            .padding(.horizontal, HeaderCollapse.horizontalPadding)
        } else {
            switch loadState {
            case .loading:
                ProgressView()
                    .tint(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .accessibilityLabel("Loading post")
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await loadPost(force: true) }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .frame(maxWidth: .infinity)
            case .loaded:
                EmptyView()
            }
        }
    }

    private var loversSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(cardLoves.count == 1 ? "Loved by" : "Loved by \(cardLoves.count)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.muted)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            ForEach(Array(cardLoves.enumerated()), id: \.element.id) { index, notice in
                loverRow(notice, showsDivider: index < cardLoves.count - 1)
            }
        }
    }

    private func loverRow(_ notice: LoveNotice, showsDivider: Bool) -> some View {
        let when = Self.relative.localizedString(for: notice.createdAt, relativeTo: Date())
        let sentence = "Loved your \(notice.style.displayName) angle"
        let summary = HStack(spacing: 14) {
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
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let actor = notice.actor {
                    Button {
                        onOpenLover(
                            FollowedPerson(
                                id: actor.id,
                                initials: actor.initials,
                                avatarPath: actor.avatarPath
                            )
                        )
                    } label: {
                        summary
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(notice.publicLabel), \(sentence), \(when)")
                    .accessibilityHint("Opens their posts")

                    if !actor.following {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.followBack(actor.id)
                        } label: {
                            Text("Follow")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.ink)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Follow \(notice.publicLabel)")
                    } else {
                        Text("Following")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.muted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                } else {
                    Button {
                        if currentCard?.hasStyle(notice.style) == true {
                            style = notice.style
                        }
                    } label: {
                        summary
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Someone, \(sentence), \(when)")
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

    private func actions(for card: HomeCard) -> AngleCardActions {
        var actions = AngleCardActions()
        if card.isOwner {
            actions.onDelete = {
                viewModel.deleteCard(card.id)
                onClose()
            }
            actions.onSetPublic = { viewModel.setPublic(card.id, isPublic: $0) }
            return actions
        }
        actions.onToggleSave = {
            viewModel.toggleSave(card.id, style: style)
        }
        return actions
    }

    private func loadPost(force: Bool = false) async {
        if force, currentCard == nil {
            loadState = .loading
        }
        async let fetchedCard = viewModel.fetchPost(id: route.id)
        async let notices: Void = viewModel.loadFollowNotificationsIfEmpty()
        let result = await fetchedCard
        _ = await notices
        switch result {
        case .loaded(let card):
            loadedCard = card
            if let initial = route.initialStyle, card.hasStyle(initial) {
                style = initial
            } else if !card.hasStyle(style) {
                style = card.openingStyle
            }
            loadState = .loaded
        case .notFound:
            if currentCard == nil {
                loadState = .failed("That post isn't available anymore.")
            }
        case .failed:
            if currentCard == nil {
                loadState = .failed("Couldn't load this post.")
            }
        case .cancelled:
            break
        }
    }
}
