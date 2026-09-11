import SwiftUI

enum ReframeCardPresentation: String, Equatable {
    case library
    case favoriteAngles
}

enum ReframeCardMenuRole: Equatable {
    case owner
    case feed
    case savedFromFeed
}

enum ReframeCardMetrics {
    static let storedMinimumHeight: CGFloat = 300
    static let overlayMinimumHeight: CGFloat = 260
    static let chromeInset: CGFloat = 16
    static let controlSize: CGFloat = 44
    static let avatarSize: CGFloat = 36
    static let sectionSpacing: CGFloat = 16
    static let chipSize: CGFloat = 36
    static let chipSizeCompact: CGFloat = 30
    static let chipSpacing: CGFloat = 8
    static let chipHitSize: CGFloat = 40
}

struct ReframeCardView: View, Equatable {
    let card: HomeCard
    var presentation: ReframeCardPresentation = .library
    var menuRole: ReframeCardMenuRole = .owner
    var openingStyle: Style? = nil
    var onDelete: () -> Void = {}
    var onToggleFavorite: (Style) -> Void = { _ in }
    var onSetPublic: (Bool) -> Void = { _ in }
    var onRemoveFromBoard: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var favoriteCardHeight: CGFloat =
        ReframeCardMetrics.storedMinimumHeight
    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var favoriteHaptic = 0
    @State private var favoriteFlipHaptic = 0
    @State private var isFavoriteFlipped = false
    @State private var showDeleteConfirm = false

    static func == (lhs: ReframeCardView, rhs: ReframeCardView) -> Bool {
        lhs.card == rhs.card
            && lhs.presentation == rhs.presentation
            && lhs.menuRole == rhs.menuRole
            && lhs.openingStyle == rhs.openingStyle
    }

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var visibleSlides: [HomeCardSlide] {
        switch presentation {
        case .library:
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
        case .favoriteAngles:
            favoriteFlipCard
        }
    }

    private var stackedCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            storedHeader

            ReframeCopyStack(
                thought: displayedThought,
                answer: activeSlide?.result.reframe
            )

            storedFooter
        }
        .frame(maxWidth: .infinity, minHeight: ReframeCardMetrics.storedMinimumHeight, alignment: .top)
        .background {
            activeAppearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
    }

    private var favoriteFlipCard: some View {
        FlipStack(progress: isFavoriteFlipped ? 1 : 0) {
            favoriteFace(
                copy: activeSlide?.result.reframe ?? "",
                font: .title3.weight(.semibold),
                foreground: theme.ink
            )
        } back: {
            favoriteFace(
                copy: displayedThought,
                font: .body.weight(.medium),
                foreground: theme.ink.opacity(0.72)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: favoriteCardHeight)
        .clipped()
        .background {
            activeAppearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
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
            storedHeader

            Text(copy)
                .font(font)
                .foregroundStyle(foreground)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(ReframeCardMetrics.chromeInset)
                .contentShape(Rectangle())
                .onTapGesture(perform: flipFavorite)

            favoriteFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var storedHeader: some View {
        HStack(spacing: 10) {
            InitialsAvatar(
                letters: card.authorInitials,
                side: ReframeCardMetrics.avatarSize,
                fill: theme.ink,
                symbol: theme.paper
            )

            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)

            Spacer(minLength: 8)

            if showsMenu {
                Menu {
                    cardMenuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(
                            width: ReframeCardMetrics.controlSize,
                            height: ReframeCardMetrics.controlSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card actions")
            }
        }
        .padding(.leading, ReframeCardMetrics.chromeInset)
        .padding(.trailing, 10)
        .padding(.top, 12)
    }

    private var storedFooter: some View {
        HStack(spacing: 10) {
            styleSelector(activeAppearance)

            Spacer(minLength: 8)

            if let style = activeStyle {
                favoriteButton(for: style)
            }
        }
        .padding(.leading, ReframeCardMetrics.chromeInset)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var favoriteFooter: some View {
        HStack(spacing: 6) {
            styleSelector(activeAppearance)

            Spacer(minLength: 4)

            if let style = activeStyle {
                favoriteButton(for: style)
            }

            Button(action: flipFavorite) {
                Image(systemName: isFavoriteFlipped ? "chevron.left" : "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(
                        width: ReframeCardMetrics.controlSize,
                        height: ReframeCardMetrics.controlSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavoriteFlipped ? "Show selected answer" : "Show thought")
        }
        .padding(.leading, ReframeCardMetrics.chromeInset)
        .padding(.trailing, 6)
        .padding(.bottom, 12)
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
                .frame(
                    width: ReframeCardMetrics.controlSize,
                    height: ReframeCardMetrics.controlSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite ? "Remove from favorite angles" : "Add to favorite angles"
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    @ViewBuilder
    private var cardMenuItems: some View {
        if hasOriginal {
            Button {
                showingOriginal.toggle()
                if presentation == .favoriteAngles {
                    showFavoriteThought()
                }
            } label: {
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
            Button("Remove from board", systemImage: "rectangle.badge.minus") {
                onRemoveFromBoard()
            }
        case .owner:
            Button {
                onSetPublic(!card.isPublic)
            } label: {
                Label(
                    card.isPublic ? "Make private" : "Make public",
                    systemImage: card.isPublic ? "lock.fill" : "globe"
                )
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }

    private var accessibilityLabel: String {
        guard let slide = activeSlide else {
            return displayedThought
        }
        if presentation == .favoriteAngles {
            return isFavoriteFlipped
                ? displayedThought
                : "\(slide.result.style.displayName) answer. \(slide.result.reframe)"
        }
        return "\(displayedThought). \(slide.result.style.displayName) answer. \(slide.result.reframe)"
    }

    private func preferredStyle() -> Style? {
        switch presentation {
        case .favoriteAngles:
            if let preferred = card.latestFavoriteStyle, visibleStyles.contains(preferred) {
                return preferred
            }
        case .library:
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
    var onRecook: (Style) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme

    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var recookHaptic = 0

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
            if hasOriginal {
                HStack {
                    Spacer(minLength: 0)
                    OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                        showingOriginal.toggle()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            ReframeCopyStack(
                thought: displayedThought,
                answer: activeResult?.reframe
            )

            overlayFooter
        }
        .frame(maxWidth: .infinity, minHeight: ReframeCardMetrics.overlayMinimumHeight, alignment: .top)
        .background {
            activeAppearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var overlayFooter: some View {
        HStack(spacing: 10) {
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

            Spacer(minLength: 6)

            recookButton(for: activeAppearance.style, ink: activeAppearance.ink)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func recookButton(for style: Style, ink: Color) -> some View {
        let isRecooking = recookingStyle == style
        return Button {
            recookHaptic += 1
            onRecook(style)
        } label: {
            HStack(spacing: 4) {
                if isRecooking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(ink)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(isRecooking ? "New \(style.displayName.lowercased()) angle…" : "New answer")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(minHeight: 40)
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

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(thought)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.ink.opacity(0.72))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ReframeCardMetrics.chromeInset)
                .padding(.top, ReframeCardMetrics.sectionSpacing)
                .padding(.bottom, ReframeCardMetrics.sectionSpacing)

            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 1)
                .padding(.horizontal, ReframeCardMetrics.chromeInset)

            if let answer {
                Text(answer)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ReframeCardMetrics.chromeInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .foregroundStyle(isSelected ? appearance.ink : faint)
            .padding(.horizontal, isSelected ? 10 : 0)
            .frame(width: isSelected ? nil : side, height: side, alignment: .center)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? appearance.ink.opacity(0.14) : faint.opacity(0.08))
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

fileprivate func stylePill(_ appearance: CardStyleAppearance) -> some View {
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
    .background(appearance.ink.opacity(0.14), in: Capsule())
    .accessibilityHidden(true)
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
