import SwiftUI

enum ReframeCardPresentation: String, Equatable {
    case library
    case tallLibrary
    case favoriteAngles
}

enum ReframeCardMenuRole: Equatable {
    case owner
    case feed
    case savedFromFeed
}

enum ReframeCardMetrics {
    static let storedMinimumHeight: CGFloat = 284
    /// Experiment (tall Home cards): one dominant card per viewport.
    static let tallChromeInset: CGFloat = 20
    static let tallRhythm: CGFloat = 16
    static let tallAvatarSize: CGFloat = 48
    static let tallSectionSpacing: CGFloat = 20
    static let tallThoughtFont: Font = .body.weight(.regular)
    static let tallAnswerFont: Font = .title2.weight(.semibold)
    static let tallAnswerLineSpacing: CGFloat = 8
    static let tallAnswerVerticalPadding: CGFloat = 18
    /// Flip-only favorites: answer on front, thought on back — grows with copy.
    static let favoriteStripMinHeight: CGFloat = 168
    /// Horizontal strip caps height; copy scrolls inside instead of clipping.
    static let favoriteStripMaxHeight: CGFloat = 288
    static let favoriteChromeInset: CGFloat = 12
    /// Header + footer chrome reserved when sizing the strip scroll region.
    static let favoriteStripChromeHeight: CGFloat = 96
    static let overlayMinimumHeight: CGFloat = 300
    static let thoughtFont: Font = .callout.weight(.regular)
    /// Flip-back thought: solo on the card, so a step up from stacked secondary copy.
    static let favoriteThoughtFont: Font = .body.weight(.medium)
    static let answerFont: Font = .body.weight(.semibold)
    static let answerLineSpacing: CGFloat = 2
    static let chromeInset: CGFloat = 16
    static let controlSize: CGFloat = 44
    static let avatarSize: CGFloat = 36
    static let sectionSpacing: CGFloat = 16
    static let chipSize: CGFloat = 36
    static let chipSizeCompact: CGFloat = 30
    static let chipSpacing: CGFloat = 8
    static let chipHitSize: CGFloat = 40
    static let lifeAreaBadgeMaxWidth: CGFloat = 148
    static let lifeAreaBadgeStripMaxWidth: CGFloat = 120
    /// Favorite footer: heart vs flip chevron (modest — not layout-breaking).
    static let favoriteHeartChevronSpacing: CGFloat = 8
}

struct ReframeCardView: View, Equatable {
    let card: HomeCard
    var presentation: ReframeCardPresentation = .library
    var menuRole: ReframeCardMenuRole = .owner
    var openingStyle: Style? = nil
    /// Profile favorite carousel: cap height and scroll long copy instead of clipping.
    var limitsFavoriteCopyHeight: Bool = false
    /// Experiment tall cards: viewport cap. The card hugs its text and only
    /// grows up to this height; the reply scrolls if a cook would pass it.
    var tallCardMaxHeight: CGFloat? = nil
    var onDelete: () -> Void = {}
    var onToggleFavorite: (Style) -> Void = { _ in }
    var onSetPublic: (Bool) -> Void = { _ in }
    var onRemoveFromBoard: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var favoriteCardMinHeight: CGFloat =
        ReframeCardMetrics.favoriteStripMinHeight
    @ScaledMetric(relativeTo: .body) private var favoriteCardMaxHeight: CGFloat =
        ReframeCardMetrics.favoriteStripMaxHeight
    @ScaledMetric(relativeTo: .body) private var favoriteStripChromeHeight: CGFloat =
        ReframeCardMetrics.favoriteStripChromeHeight
    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var favoriteHaptic = 0
    @State private var favoriteFlipHaptic = 0
    @State private var heartBurst = 0
    @State private var heartScale: CGFloat = 1
    @State private var isFavoriteFlipped = false
    @State private var showDeleteConfirm = false
    /// Uncapped height of the tall card, measured off-screen. Drives the reply scroll.
    @State private var tallIdealHeight: CGFloat = 0

    static func == (lhs: ReframeCardView, rhs: ReframeCardView) -> Bool {
        lhs.card == rhs.card
            && lhs.presentation == rhs.presentation
            && lhs.menuRole == rhs.menuRole
            && lhs.openingStyle == rhs.openingStyle
            && lhs.limitsFavoriteCopyHeight == rhs.limitsFavoriteCopyHeight
            && lhs.tallCardMaxHeight == rhs.tallCardMaxHeight
    }

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var visibleSlides: [HomeCardSlide] {
        switch presentation {
        case .library, .tallLibrary:
            return card.slides
        case .favoriteAngles:
            return card.slides.filter(\.isFavorite)
        }
    }

    private var visibleStyles: [Style] {
        visibleSlides.map(\.result.style)
    }

    private var activeSlide: HomeCardSlide? {
        guard let selectedStyle,
              let match = visibleSlides.first(where: { $0.result.style == selectedStyle })
        else {
            return visibleSlides.first
        }
        return match
    }

    private var activeStyle: Style? {
        activeSlide?.result.style
    }

    private var activeAppearance: CardStyleAppearance {
        CardStyleAppearance(style: activeStyle ?? card.spotlightStyle)
    }

    private var displayedThought: String {
        showingOriginal ? (card.thoughtOriginal ?? card.thought) : card.thought
    }

    private var hasOriginal: Bool {
        guard let original = card.thoughtOriginal else {
            return false
        }
        return original != card.thought
    }

    private var showsMenu: Bool {
        switch menuRole {
        case .owner, .savedFromFeed:
            return true
        case .feed:
            return hasOriginal
        }
    }

    var body: some View {
        menuedCard
            .onAppear {
                if selectedStyle == nil {
                    setSelectedStyleWithoutAnimation(preferredStyle())
                }
            }
            .onChange(of: openingStyle) { _, _ in
                setSelectedStyleWithoutAnimation(preferredStyle())
            }
            .onChange(of: presentation) { _, _ in
                setSelectedStyleWithoutAnimation(preferredStyle())
            }
            .onChange(of: visibleStyles) { _, styles in
                guard let selectedStyle, styles.contains(selectedStyle) else {
                    setSelectedStyleWithoutAnimation(preferredStyle())
                    return
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteFlipHaptic)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .confirmationDialog(
                "Delete this card?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var menuedCard: some View {
        if showsMenu {
            cardBody
                .contextMenu {
                    cardMenuItems
                }
        } else {
            cardBody
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch presentation {
        case .library:
            stackedCardBody
        case .tallLibrary:
            tallStackedCardBody
        case .favoriteAngles:
            favoriteFlipCard
        }
    }

    private var stackedCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            storedHeader

            ReframeCopyStack(
                thought: displayedThought,
                answer: activeSlide?.result.reframe,
                answerColor: activeAppearance.responseInk
            )

            storedFooter
        }
        .frame(maxWidth: .infinity, minHeight: ReframeCardMetrics.storedMinimumHeight, alignment: .top)
        .background {
            activeAppearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
    }

    /// One column. It hugs the text. The reply scrolls only when that column
    /// measures taller than the live viewport cap.
    private var tallStackedCardBody: some View {
        tallColumn(scrollsAnswer: tallReplyScrolls)
            .fixedSize(horizontal: false, vertical: !tallReplyScrolls)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: tallReplyScrolls ? tallCardMaxHeight : nil, alignment: .top)
            .background {
                activeAppearance.washFill(over: theme.surface)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: TallIdealHeightKey.self, value: proxy.size.height)
                }
            }
            .clipShape(cardShape)
            .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
            .onPreferenceChange(TallIdealHeightKey.self) { newValue in
                guard !tallReplyScrolls, newValue > 1, abs(newValue - tallIdealHeight) > 1 else { return }
                tallIdealHeight = newValue
            }
            .onChange(of: activeSlide?.result.reframe) { _, _ in
                tallIdealHeight = 0
            }
    }

    private var tallReplyScrolls: Bool {
        guard let cap = tallCardMaxHeight, cap > 1, tallIdealHeight > 1 else { return false }
        return tallIdealHeight > cap + 1
    }

    private func tallColumn(scrollsAnswer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tallStoredHeader

            ReframeCopyStack(
                thought: displayedThought,
                answer: activeSlide?.result.reframe,
                answerColor: activeAppearance.responseInk,
                thoughtFont: ReframeCardMetrics.tallThoughtFont,
                answerFont: ReframeCardMetrics.tallAnswerFont,
                answerLineSpacing: ReframeCardMetrics.tallAnswerLineSpacing,
                chromeInset: ReframeCardMetrics.tallRhythm,
                sectionSpacing: ReframeCardMetrics.tallSectionSpacing,
                answerVerticalPadding: ReframeCardMetrics.tallAnswerVerticalPadding,
                model: card.model,
                modelFill: activeAppearance.ink,
                scrollsAnswer: scrollsAnswer
            )
            .frame(maxHeight: scrollsAnswer ? .infinity : nil, alignment: .top)

            tallStoredFooter
        }
    }

    private var favoriteFlipCard: some View {
        FlipStack(progress: isFavoriteFlipped ? 1 : 0) {
            favoriteFace(
                copy: activeSlide?.result.reframe ?? "",
                font: ReframeCardMetrics.answerFont,
                foreground: activeAppearance.responseInk
            )
            .background {
                activeAppearance.washFill(over: theme.surface)
            }
        } back: {
            favoriteFace(
                copy: displayedThought,
                font: ReframeCardMetrics.favoriteThoughtFont,
                foreground: theme.sub
            )
            .background {
                theme.surface
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: favoriteCardMinHeight)
        .frame(maxHeight: limitsFavoriteCopyHeight ? favoriteCardMaxHeight : nil)
        .clipShape(cardShape)
        .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
        .accessibilityHint(isFavoriteFlipped ? "Shows the selected answer" : "Shows the thought")
        .accessibilityAction(named: isFavoriteFlipped ? "Show answer" : "Show thought") {
            flipFavorite()
        }
    }

    private func favoriteFace(
        copy: String,
        font: Font,
        foreground: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            favoriteHeader

            favoriteCopyBlock(copy: copy, font: font, foreground: foreground)

            Spacer(minLength: 0)

            favoriteFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func favoriteCopyBlock(copy: String, font: Font, foreground: Color) -> some View {
        let text = Text(copy)
            .font(font)
            .foregroundStyle(foreground)
            .lineSpacing(ReframeCardMetrics.answerLineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReframeCardMetrics.favoriteChromeInset)
            .contentShape(Rectangle())
            .onTapGesture(perform: flipFavorite)

        if limitsFavoriteCopyHeight {
            let scrollCap = max(72, favoriteCardMaxHeight - favoriteStripChromeHeight)
            ScrollView(.vertical, showsIndicators: false) {
                text
            }
            .frame(maxHeight: scrollCap)
        } else {
            text
        }
    }

    private var storedHeader: some View {
        HStack(spacing: 10) {
            AuthorMark(
                initials: card.authorInitials,
                avatarPath: card.authorAvatarPath,
                prefersLocalPhoto: card.isOwner,
                side: ReframeCardMetrics.avatarSize,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            headerTrailingCluster(menuGlyphSize: 17)
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
    }

    private var tallStoredHeader: some View {
        HStack(spacing: 12) {
            AuthorMark(
                initials: card.authorInitials,
                avatarPath: card.authorAvatarPath,
                prefersLocalPhoto: card.isOwner,
                side: ReframeCardMetrics.tallAvatarSize,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            headerTrailingCluster(
                menuGlyphSize: 17,
                badgeIconSize: 16,
                badgeFont: .subheadline.weight(.medium)
            )
        }
        .padding(.horizontal, ReframeCardMetrics.tallRhythm)
        .padding(.top, ReframeCardMetrics.tallRhythm)
    }

    private var favoriteHeader: some View {
        HStack(spacing: 8) {
            AuthorMark(
                initials: card.authorInitials,
                avatarPath: card.authorAvatarPath,
                prefersLocalPhoto: card.isOwner,
                side: 32,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .layoutPriority(-1)

            Spacer(minLength: 4)

            headerTrailingCluster(menuGlyphSize: 16)
        }
        .padding(.horizontal, ReframeCardMetrics.favoriteChromeInset)
        .padding(.top, ReframeCardMetrics.favoriteChromeInset)
    }

    @ViewBuilder
    private func headerTrailingCluster(
        menuGlyphSize: CGFloat,
        badgeIconSize: CGFloat = 12,
        badgeFont: Font = .caption.weight(.medium)
    ) -> some View {
        if showsMenu {
            cardActionsTrigger(
                menuGlyphSize: menuGlyphSize,
                badgeIconSize: badgeIconSize,
                badgeFont: badgeFont
            )
        } else if let lifeArea = card.lifeAreaPresentation {
            LifeAreaBadge(
                category: lifeArea.category,
                label: lifeAreaLabel(lifeArea),
                maxWidth: limitsFavoriteCopyHeight
                    ? ReframeCardMetrics.lifeAreaBadgeStripMaxWidth
                    : ReframeCardMetrics.lifeAreaBadgeMaxWidth,
                iconSize: badgeIconSize,
                labelFont: badgeFont
            )
        }
    }

    /// Category + ⋯ stay visually tight; tap anywhere on the cluster for the same menu as long-press.
    private func cardActionsTrigger(
        menuGlyphSize: CGFloat,
        badgeIconSize: CGFloat = 12,
        badgeFont: Font = .caption.weight(.medium)
    ) -> some View {
        Menu {
            cardMenuItems
        } label: {
            HStack(spacing: 8) {
                if let lifeArea = card.lifeAreaPresentation {
                    LifeAreaBadge(
                        category: lifeArea.category,
                        label: lifeAreaLabel(lifeArea),
                        maxWidth: limitsFavoriteCopyHeight
                            ? ReframeCardMetrics.lifeAreaBadgeStripMaxWidth
                            : ReframeCardMetrics.lifeAreaBadgeMaxWidth,
                        iconSize: badgeIconSize,
                        labelFont: badgeFont
                    )
                    .accessibilityHidden(true)
                }

                Image(systemName: "ellipsis")
                    .font(.system(size: menuGlyphSize, weight: .semibold))
                    .foregroundStyle(theme.muted)
            }
            .frame(minHeight: ReframeCardMetrics.controlSize, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityLabel("Card actions")
    }

    private func lifeAreaLabel(_ presentation: (category: ThoughtCategory, label: String)) -> String {
        guard limitsFavoriteCopyHeight, presentation.category != .other else {
            return presentation.label
        }
        return presentation.category.compactDisplayName
    }

    private var storedFooter: some View {
        HStack(spacing: 10) {
            styleSelector(activeAppearance)

            Spacer(minLength: 8)

            if let style = activeStyle {
                favoriteButton(for: style)
            }
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, 12)
        .padding(.bottom, ReframeCardMetrics.chromeInset)
    }

    private var tallStoredFooter: some View {
        HStack(spacing: 12) {
            styleSelector(activeAppearance)

            Spacer(minLength: 8)

            if let style = activeStyle {
                tallFavoriteButton(for: style, tint: activeAppearance.ink)
            }
        }
        .padding(.horizontal, ReframeCardMetrics.tallRhythm)
        .padding(.top, ReframeCardMetrics.tallSectionSpacing)
        .padding(.bottom, ReframeCardMetrics.tallRhythm)
    }

    private var favoriteFooter: some View {
        HStack(spacing: 6) {
            styleSelector(activeAppearance)

            Spacer(minLength: 4)

            HStack(spacing: ReframeCardMetrics.favoriteHeartChevronSpacing) {
                if let style = activeStyle {
                    favoriteButton(for: style)
                }

                Button(action: flipFavorite) {
                    chromeIcon(
                        isFavoriteFlipped ? "chevron.left" : "chevron.right",
                        size: 16,
                        color: theme.muted
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavoriteFlipped ? "Show selected answer" : "Show thought")
            }
        }
        .padding(.horizontal, ReframeCardMetrics.favoriteChromeInset)
        .padding(.bottom, ReframeCardMetrics.favoriteChromeInset)
    }

    @ViewBuilder
    private func styleSelector(_ appearance: CardStyleAppearance) -> some View {
        if visibleStyles.count > 1 {
            StyleChipRow(
                styles: visibleStyles,
                selected: appearance.style,
                faint: theme.faint
            ) { style in
                selectedStyle = style
            }
        } else {
            stylePill(appearance)
        }
    }

    private func favoriteButton(for style: Style) -> some View {
        let isFavorite = card.isStyleFavorited(style)
        let slop = chromeIconSlop(glyphSize: 17)
        return Button {
            favoriteHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.58)) {
                onToggleFavorite(style)
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFavorite ? theme.ink : theme.muted)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.4), value: favoriteHaptic)
                .padding(slop)
                .contentShape(Rectangle())
                .padding(-slop)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite ? "Remove from favorite angles" : "Add to favorite angles"
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    /// Tall Home heart: style-tinted circle, a scale-up, and a burst of hearts that rise and fade.
    private func tallFavoriteButton(for style: Style, tint: Color) -> some View {
        let isFavorite = card.isStyleFavorited(style)
        return Button {
            let liking = !isFavorite
            favoriteHaptic += 1
            if liking, !reduceMotion {
                heartBurst += 1
                heartScale = 1.28
                withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
                    heartScale = 1
                }
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.58)) {
                onToggleFavorite(style)
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? tint : theme.muted)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(heartScale)
                .frame(width: ReframeCardMetrics.chipSize, height: ReframeCardMetrics.chipSize)
                .background(tint.opacity(0.08), in: Circle())
                .overlay {
                    RisingHeartBurst(trigger: heartBurst, tint: tint)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite ? "Remove from favorite angles" : "Add to favorite angles"
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    private func chromeIcon(
        _ systemName: String,
        size: CGFloat,
        color: Color
    ) -> some View {
        let slop = chromeIconSlop(glyphSize: size)
        return Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .padding(slop)
            .contentShape(Rectangle())
            .padding(-slop)
    }

    private func chromeIconSlop(glyphSize: CGFloat) -> CGFloat {
        max(0, (ReframeCardMetrics.controlSize - glyphSize) / 2)
    }

    @ViewBuilder
    private var cardMenuItems: some View {
        if hasOriginal {
            Button(action: toggleOriginalLanguage) {
                Label(
                    showingOriginal ? "Show English" : "Show original",
                    systemImage: showingOriginal ? "character.bubble.fill" : "character.bubble"
                )
            }
        }

        switch menuRole {
        case .feed:
            EmptyView()
        case .savedFromFeed:
            cardDestructiveMenuButton(
                "Remove from board",
                systemImage: "rectangle.badge.minus",
                action: onRemoveFromBoard
            )
        case .owner:
            Button {
                onSetPublic(!card.isPublic)
            } label: {
                Label(
                    card.isPublic ? "Make private" : "Make public",
                    systemImage: card.isPublic ? "lock.fill" : "globe"
                )
            }

            cardDestructiveMenuButton("Delete", systemImage: "trash") {
                showDeleteConfirm = true
            }
        }
    }

    private func cardDestructiveMenuButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color(uiColor: .systemRed))
        }
        .tint(Color(uiColor: .systemRed))
    }

    private func toggleOriginalLanguage() {
        showingOriginal.toggle()
        if presentation == .favoriteAngles {
            showFavoriteThought()
        }
    }

    private var accessibilityLabel: String {
        let prefix = card.lifeAreaPresentation.map { "\($0.label). " } ?? ""
        guard let slide = activeSlide else {
            return prefix + displayedThought
        }
        if presentation == .favoriteAngles {
            let body = isFavoriteFlipped
                ? displayedThought
                : "\(slide.result.style.displayName) answer. \(slide.result.reframe)"
            return prefix + body
        }
        return prefix
            + "\(displayedThought). \(slide.result.style.displayName) answer. \(slide.result.reframe)"
    }

    private func preferredStyle() -> Style? {
        switch presentation {
        case .favoriteAngles:
            if let preferred = card.latestFavoriteStyle, visibleStyles.contains(preferred) {
                return preferred
            }
        case .library, .tallLibrary:
            if let openingStyle, visibleStyles.contains(openingStyle) {
                return openingStyle
            }
            if visibleStyles.contains(card.spotlightStyle) {
                return card.spotlightStyle
            }
        }
        return visibleStyles.first
    }

    private func setSelectedStyleWithoutAnimation(_ style: Style?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStyle = style
        }
    }

    private func flipFavorite() {
        favoriteFlipHaptic += 1
        withAnimation(
            reduceMotion ? nil : .timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)
        ) {
            isFavoriteFlipped.toggle()
        }
    }

    private func showFavoriteThought() {
        guard !isFavoriteFlipped else {
            return
        }
        favoriteFlipHaptic += 1
        withAnimation(
            reduceMotion ? nil : .timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)
        ) {
            isFavoriteFlipped = true
        }
    }
}

struct OverlayProposalCard: View {
    let thought: String
    var thoughtOriginal: String?
    let results: [ReframeResult]
    var recookingStyle: Style?
    var identityStore: ProfileIdentityStore? = nil
    @Binding var isPublic: Bool
    var allowsRecook: Bool = true
    var onRecook: (Style) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme

    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var recookHaptic = 0
    @State private var privacyHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var activeResult: ReframeResult? {
        guard let selectedStyle,
              let match = results.first(where: { $0.style == selectedStyle })
        else {
            return results.first
        }
        return match
    }

    private var activeAppearance: CardStyleAppearance {
        CardStyleAppearance(style: activeResult?.style ?? .stoic)
    }

    private var hasOriginal: Bool {
        guard let thoughtOriginal else {
            return false
        }
        return thoughtOriginal != thought
    }

    private var displayedThought: String {
        showingOriginal ? (thoughtOriginal ?? thought) : thought
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            overlayHeader

            ReframeCopyStack(
                thought: displayedThought,
                answer: activeResult?.reframe,
                answerColor: activeAppearance.responseInk
            )

            overlayFooter
        }
        .frame(maxWidth: .infinity, minHeight: ReframeCardMetrics.overlayMinimumHeight, alignment: .top)
        .background {
            activeAppearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
        .onAppear {
            if selectedStyle == nil {
                setSelectedStyleWithoutAnimation(results.first?.style)
            }
        }
        .onChange(of: results.map(\.style)) { _, styles in
            guard let selectedStyle, styles.contains(selectedStyle) else {
                setSelectedStyleWithoutAnimation(styles.first)
                return
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: recookHaptic)
        .sensoryFeedback(.selection, trigger: privacyHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var overlayHeader: some View {
        HStack(spacing: 10) {
            AuthorMark(
                initials: identityStore?.avatarLetters ?? identityStore?.serverInitials ?? UserInitials.letters,
                avatarPath: identityStore?.avatarPath,
                prefersLocalPhoto: true,
                side: ReframeCardMetrics.avatarSize,
                fill: theme.ink,
                symbol: theme.paper
            )
            .accessibilityHidden(true)

            Spacer(minLength: 4)

            overlayPrivacyToggle

            if hasOriginal {
                OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                    showingOriginal.toggle()
                }
            }
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
    }

    private var overlayPrivacyToggle: some View {
        Button {
            privacyHaptic += 1
            isPublic.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isPublic ? "globe" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(isPublic ? "Public" : "Private")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(theme.ink.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPublic ? "Public" : "Private")
        .accessibilityHint(isPublic ? "Makes this card private" : "Makes this card public")
        .accessibilityAddTraits(.isButton)
    }

    private var overlayFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if results.count > 1 {
                StyleChipRow(
                    styles: results.map(\.style),
                    selected: activeAppearance.style,
                    faint: theme.faint
                ) { style in
                    selectedStyle = style
                }
            } else {
                stylePill(activeAppearance)
            }

            if allowsRecook {
                recookButton(for: activeAppearance.style, ink: activeAppearance.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, 12)
        .padding(.bottom, ReframeCardMetrics.chromeInset)
    }

    private func recookButton(for style: Style, ink: Color) -> some View {
        let isRecooking = recookingStyle == style
        return Button {
            recookHaptic += 1
            onRecook(style)
        } label: {
            HStack(spacing: 6) {
                if isRecooking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(ink)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isRecooking ? "New \(style.displayName.lowercased()) angle…" : "New answer")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(ink.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(recookingStyle != nil)
        .opacity(recookingStyle == nil || isRecooking ? 1 : 0.45)
        .accessibilityLabel(
            isRecooking
                ? "New \(style.displayName.lowercased()) angle"
                : "New \(style.displayName) answer"
        )
    }

    private var accessibilityLabel: String {
        guard let result = activeResult else {
            return displayedThought
        }
        return "\(displayedThought). \(result.style.displayName) answer. \(result.reframe)"
    }

    private func setSelectedStyleWithoutAnimation(_ style: Style?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStyle = style
        }
    }
}

private struct ReframeCopyStack: View {
    let thought: String
    let answer: String?
    var answerColor: Color?
    var thoughtFont: Font = ReframeCardMetrics.thoughtFont
    var answerFont: Font = ReframeCardMetrics.answerFont
    var answerLineSpacing: CGFloat = ReframeCardMetrics.answerLineSpacing
    var chromeInset: CGFloat = ReframeCardMetrics.chromeInset
    var sectionSpacing: CGFloat = ReframeCardMetrics.sectionSpacing
    var answerVerticalPadding: CGFloat = 14
    var model: LlmModel? = nil
    var modelFill: Color? = nil
    /// When the card is at the viewport cap, only the reply scrolls.
    var scrollsAnswer: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var resolvedAnswerColor: Color {
        answerColor ?? theme.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(thought)
                .font(thoughtFont)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, chromeInset)
                .padding(.top, sectionSpacing)
                .padding(.bottom, sectionSpacing)

            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 1)
                .padding(.horizontal, chromeInset)

            if let answer {
                answerRow(answer)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: scrollsAnswer ? .infinity : nil,
            alignment: .topLeading
        )
    }

    /// Tall cards pass a model: icon and name share one row. The reply stays full width under it.
    @ViewBuilder
    private func answerRow(_ answer: String) -> some View {
        VStack(alignment: .leading, spacing: model == nil ? 0 : ReframeCardMetrics.tallRhythm) {
            if let model {
                HStack(spacing: 10) {
                    ModelLogo(model: model, side: 18)
                        .frame(width: ReframeCardMetrics.chipSize, height: ReframeCardMetrics.chipSize)
                        .background((modelFill ?? theme.ink).opacity(0.08), in: Circle())

                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Written by \(model.displayName)")
            }

            Text(answer)
                .font(answerFont)
                .foregroundStyle(resolvedAnswerColor)
                .lineSpacing(answerLineSpacing)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(TallAnswerScroll(enabled: scrollsAnswer))
        }
        .padding(.horizontal, chromeInset)
        .padding(.top, model == nil ? answerVerticalPadding : ReframeCardMetrics.tallRhythm)
        .padding(.bottom, model == nil ? answerVerticalPadding : 0)
        .frame(maxHeight: scrollsAnswer ? .infinity : nil, alignment: .top)
    }
}

/// Reads the tall card’s laid-out height while it is still hugging its text.
private struct TallIdealHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TallAnswerScroll: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            ScrollView {
                content
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            content
        }
    }
}

private struct OriginalToggle: View {
    let showingOriginal: Bool
    let ink: Color
    let action: () -> Void

    @State private var haptic = 0

    var body: some View {
        Button {
            haptic += 1
            action()
        } label: {
            Image(systemName: showingOriginal ? "character.bubble.fill" : "character.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .background(ink.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .accessibilityLabel(showingOriginal ? "Show the English version" : "Show the original wording")
    }
}

/// Selected chip is a labeled pill; the rest stay circles and morph only on a user tap.
private struct StyleChipRow: View {
    let styles: [Style]
    let selected: Style
    let faint: Color
    let onSelect: (Style) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectHaptic = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(side: ReframeCardMetrics.chipSize)
            row(side: ReframeCardMetrics.chipSizeCompact)
        }
        .sensoryFeedback(.selection, trigger: selectHaptic)
    }

    private func row(side: CGFloat) -> some View {
        HStack(spacing: ReframeCardMetrics.chipSpacing) {
            ForEach(styles, id: \.self) { style in
                chip(style, side: side)
            }
        }
    }

    private func chip(_ style: Style, side: CGFloat) -> some View {
        let appearance = CardStyleAppearance(style: style)
        let isSelected = style == selected
        let glyph: CGFloat = side >= ReframeCardMetrics.chipSize ? 14 : 12
        let slop = (ReframeCardMetrics.chipHitSize - side) / 2

        return Button {
            guard style != selected else {
                return
            }
            selectHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)) {
                onSelect(style)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: appearance.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: glyph, weight: .semibold))

                if isSelected {
                    Text(style.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.84, anchor: .leading)
                                ),
                                removal: .opacity.combined(
                                    with: .scale(scale: 0.84, anchor: .leading)
                                )
                            )
                        )
                }
            }
            .foregroundStyle(
                isSelected
                    ? appearance.ink
                    : appearance.ink.opacity(appearance.chipUnselectedInkOpacity(for: colorScheme))
            )
            .padding(.horizontal, isSelected ? 10 : 0)
            .frame(width: isSelected ? nil : side, height: side, alignment: .center)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        appearance.ink.opacity(
                            isSelected
                                ? appearance.chipFillOpacity(for: colorScheme)
                                : appearance.chipUnselectedFillOpacity(for: colorScheme)
                        )
                    )
            }
            .padding(slop)
            .contentShape(Capsule())
            .padding(-slop)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.displayName) answer")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct LifeAreaBadge: View {
    let category: ThoughtCategory
    let label: String
    var maxWidth: CGFloat = ReframeCardMetrics.lifeAreaBadgeMaxWidth
    var iconSize: CGFloat = 12
    var labelFont: Font = .caption.weight(.medium)

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            Text(label)
                .font(labelFont)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(theme.sub)
        .frame(maxWidth: maxWidth, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Life area, \(label)")
    }
}

fileprivate struct StylePill: View {
    let appearance: CardStyleAppearance

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: appearance.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))

            Text(appearance.style.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(appearance.ink)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(
            appearance.ink.opacity(appearance.chipFillOpacity(for: colorScheme)),
            in: Capsule()
        )
        .accessibilityHidden(true)
    }
}

fileprivate func stylePill(_ appearance: CardStyleAppearance) -> some View {
    StylePill(appearance: appearance)
}

/// Favorite angles keep equal-height faces so their horizontal strip stays level.
private struct FlipStack<Front: View, Back: View>: View, Animatable {
    var progress: CGFloat
    var front: Front
    var back: Back

    init(
        progress: CGFloat,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.progress = progress
        self.front = front()
        self.back = back()
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showingBack = progress > 0.5

        ZStack {
            front
                .opacity(showingBack ? 0 : 1)
                .allowsHitTesting(!showingBack)

            back
                .scaleEffect(x: -1, y: 1)
                .opacity(showingBack ? 1 : 0)
                .allowsHitTesting(showingBack)
        }
        .rotation3DEffect(
            .radians(Double(progress) * .pi),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.55
        )
        .compositingGroup()
    }
}

/// Small hearts that launch upward from the tall-card heart and fade out.
private struct RisingHeartBurst: View {
    let trigger: Int
    let tint: Color

    var body: some View {
        ZStack {
            if trigger > 0 {
                ForEach(0..<6, id: \.self) { index in
                    RisingHeart(index: index, tint: tint)
                }
                .id(trigger)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RisingHeart: View {
    let index: Int
    let tint: Color

    @State private var launched = false

    private var drift: CGFloat {
        let drifts: [CGFloat] = [-22, -12, -4, 8, 16, 24]
        return drifts[index % drifts.count]
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: index.isMultiple(of: 2) ? 11 : 14, weight: .semibold))
            .foregroundStyle(tint)
            .offset(x: launched ? drift : drift * 0.15, y: launched ? -160 - CGFloat(index * 12) : 6)
            .scaleEffect(launched ? 0.3 : 0.9)
            .opacity(launched ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: 1.15).delay(Double(index) * 0.04)) {
                    launched = true
                }
            }
    }
}

/// Photo when the author has one. Initials stay visible while it loads and if it fails.
struct AuthorMark: View {
    var initials: String
    var avatarPath: String?
    var prefersLocalPhoto = false
    var side: CGFloat
    var fill: Color
    var symbol: Color

    @Environment(\.profileIdentity) private var identity

    var body: some View {
        ZStack {
            InitialsAvatar(letters: shownInitials, side: side, fill: fill, symbol: symbol)
            if prefersLocalPhoto, let image = identity?.photo {
                fitted(Image(uiImage: image))
            } else if let url = remoteURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        fitted(image)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var shownInitials: String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Y" : trimmed
    }

    private func fitted(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(Circle())
    }

    private var remoteURL: URL? {
        guard let avatarPath, !avatarPath.isEmpty else { return nil }
        guard var components = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let pieces = avatarPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0])
        components.path = path.hasPrefix("/") ? path : "/" + path
        if pieces.count > 1, !pieces[1].isEmpty {
            components.query = String(pieces[1])
        }
        return components.url
    }
}
