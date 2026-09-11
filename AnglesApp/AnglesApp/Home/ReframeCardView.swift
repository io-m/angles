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
    /// Full-width cell on iPhone 14 Pro Max (~398pt). Chrome hugs the copy; height
    /// fits max thought (140) and max reframe (190) at real type without a dead band.
    static let baseHeight: CGFloat = 228
    /// Slightly smaller and heavier than `.title3.regular` (20pt); still larger than the answer (`.callout.medium`).
    static let thoughtSize: CGFloat = 18
    static let chromeInset: CGFloat = 16
    static let controlSize: CGFloat = 32
    static let copyTopPad: CGFloat = 8
    static let copyBottomPad: CGFloat = 8
    /// Visual circle; compact is the strip fallback. Hit target is `chipHitSize`.
    static let chipSize: CGFloat = 36
    static let chipSizeCompact: CGFloat = 30
    static let chipSpacing: CGFloat = 8
    static let chipHitSize: CGFloat = 40

    static var contentBottomPad: CGFloat { chromeInset + controlSize }
    /// Top chrome fits the chip hit area; heart and initials sit centered in it.
    static var topControlHeight: CGFloat { max(controlSize, chipHitSize) }
    /// Top chrome band: style chips / initials leading, heart trailing. Nothing in this
    /// band flips the card.
    static var topBandHeight: CGFloat { chromeInset + topControlHeight }
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
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = ReframeCardMetrics.baseHeight
    @ScaledMetric(relativeTo: .title3) private var thoughtSize: CGFloat = ReframeCardMetrics.thoughtSize
    @State private var isFlipped = false
    @State private var showingOriginal = false
    /// Explicit selection, not a value read back off a scroll offset.
    @State private var selectedStyle: Style?
    @State private var flipHaptic = 0
    @State private var favoriteHaptic = 0
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

    private var showingThought: Bool {
        isFlipped
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
            // A heart never moves the selection; only a style leaving the card does.
            .onChange(of: visibleStyles) { _, styles in
                guard let selectedStyle, styles.contains(selectedStyle) else {
                    setSelectedStyleWithoutAnimation(preferredStyle())
                    return
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteHaptic)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(showingThought ? "Shows the answers" : "Shows the original thought")
            .accessibilityAction(named: showingThought ? "Show answers" : "Show original thought") {
                flip()
            }
            .confirmationDialog("Delete this card?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
    }

    /// Long press replaces the ⋯ button: the top-trailing slot is the heart's now.
    @ViewBuilder
    private var menuedCard: some View {
        if showsMenu {
            clippedCard
                .contextMenu {
                    cardMenuItems
                }
        } else {
            clippedCard
        }
    }

    private var accessibilityLabel: String {
        if showingThought {
            return card.thought
        }

        if let slide = activeSlide {
            return "\(slide.result.style.displayName) answer. \(slide.result.reframe)"
        }

        return card.thought
    }

    private var clippedCard: some View {
        FlipStack(progress: isFlipped ? 1 : 0) {
            answerFace
        } back: {
            thoughtFace
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipped()
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.shadowSoft, radius: 10, y: 3)
        .overlay(alignment: .bottom) {
            bottomChrome
        }
    }

    private var thoughtFace: some View {
        cardFace {
            InitialsAvatar(
                letters: card.authorInitials,
                side: ReframeCardMetrics.controlSize,
                fill: theme.ink,
                symbol: theme.paper
            )
        } trailing: {
            EmptyView()
        } middle: {
            copyBand(
                Text(showingOriginal ? (card.thoughtOriginal ?? card.thought) : card.thought)
                    .font(.system(size: thoughtSize, weight: .medium))
                    .foregroundStyle(theme.ink)
            )
        }
        .background(theme.surface)
    }

    private var hasOriginal: Bool {
        guard let original = card.thoughtOriginal else {
            return false
        }

        return original != card.thought
    }

    private var activeAppearance: CardStyleAppearance {
        CardStyleAppearance(style: activeStyle ?? card.spotlightStyle)
    }

    /// The copy no longer pages, so a horizontal drag anywhere on the card belongs to the
    /// enclosing strip. Styles switch from the chips in the top band.
    private var answerFace: some View {
        let appearance = activeAppearance

        return cardFace {
            styleSelector(appearance)
        } trailing: {
            if let style = activeStyle {
                favoriteButton(for: style)
            }
        } middle: {
            if let slide = activeSlide {
                answerCopy(slide.result)
            }
        }
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    /// One chip per angle this card actually carries. A single-angle card keeps the named
    /// pill: there is nothing to switch to.
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

    /// Three bands: chrome, the flip target, chrome. The bottom band is empty space the
    /// `bottomChrome` overlay draws into.
    private func cardFace<Top: View, Trailing: View, Middle: View>(
        @ViewBuilder top: () -> Top,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder middle: () -> Middle
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                top()

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                trailing()
            }
            .frame(height: ReframeCardMetrics.topControlHeight)
            .padding(.horizontal, ReframeCardMetrics.chromeInset)
            .padding(.top, ReframeCardMetrics.chromeInset)

            middle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .frame(height: ReframeCardMetrics.contentBottomPad)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bottomChrome: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .frame(height: ReframeCardMetrics.controlSize, alignment: .leading)
                .allowsHitTesting(false)

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            flipButton
        }
        .padding(ReframeCardMetrics.chromeInset)
    }

    private func answerCopy(_ result: ReframeResult) -> some View {
        copyBand(
            Text(result.reframe)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.ink)
        )
    }

    /// One tap target for the whole middle band, including the empty space under the copy.
    private func copyBand(_ copy: Text) -> some View {
        copy
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, ReframeCardMetrics.chromeInset)
            .padding(.top, ReframeCardMetrics.copyTopPad)
            .padding(.bottom, ReframeCardMetrics.copyBottomPad)
            .contentShape(Rectangle())
            .onTapGesture(perform: flip)
    }

    private var showsMenu: Bool {
        switch menuRole {
        case .owner, .savedFromFeed:
            return true
        case .feed:
            return hasOriginal
        }
    }

    @ViewBuilder
    private var cardMenuItems: some View {
        if hasOriginal {
            Button {
                showingOriginal.toggle()
                if !showingThought {
                    flip()
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

    private func favoriteButton(for style: Style) -> some View {
        let isFavorite = card.isStyleFavorited(style)
        return Button {
            favoriteHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.58)) {
                onToggleFavorite(style)
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? theme.ink : theme.muted)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.4), value: favoriteHaptic)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite ? "Remove from favorite angles" : "Add to favorite angles"
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    /// The discoverable half of the flip; the copy band keeps the gesture.
    private var flipButton: some View {
        Button(action: flip) {
            Image(systemName: showingThought ? "chevron.left" : "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingThought ? "Show answers" : "Show the original thought")
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

    private func flip() {
        flipHaptic += 1

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isFlipped.toggle()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)) {
            isFlipped.toggle()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = ReframeCardMetrics.baseHeight
    @ScaledMetric(relativeTo: .title3) private var thoughtSize: CGFloat = ReframeCardMetrics.thoughtSize
    @State private var isFlipped = false
    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var flipHaptic = 0
    @State private var recookHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var showingThought: Bool {
        isFlipped
    }

    private var activeResult: ReframeResult? {
        guard let selectedStyle,
              let match = results.first(where: { $0.style == selectedStyle })
        else {
            return results.first
        }

        return match
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                FlipStack(progress: isFlipped ? 1 : 0) {
                    answerFace
                } back: {
                    thoughtFace
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                if showingThought && hasOriginal {
                    OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                        showingOriginal.toggle()
                    }
                    .padding(ReframeCardMetrics.chromeInset)
                    .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipShape(cardShape)
            .overlay {
                cardShape.strokeBorder(theme.cardHairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: theme.shadowSoft, radius: 10, y: 3)
            .contentShape(cardShape)
        }
        .frame(maxWidth: .infinity)
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
        .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: recookHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(showingThought ? "Shows the answers" : "Shows the original thought")
        .accessibilityAction(named: showingThought ? "Show answers" : "Show original thought") {
            flip()
        }
    }

    private var accessibilityLabel: String {
        if showingThought {
            return thought
        }

        guard let result = activeResult else {
            return "Answers"
        }

        return "\(result.style.displayName) reframe. \(result.reframe)"
    }

    private var hasOriginal: Bool {
        guard let thoughtOriginal else {
            return false
        }

        return thoughtOriginal != thought
    }

    private var thoughtFace: some View {
        cardFace {
            InitialsAvatar(
                letters: UserInitials.letters,
                side: ReframeCardMetrics.controlSize,
                fill: theme.ink,
                symbol: theme.paper
            )
        } middle: {
            copyBand(
                Text(showingOriginal ? (thoughtOriginal ?? thought) : thought)
                    .font(.system(size: thoughtSize, weight: .medium))
                    .foregroundStyle(theme.ink)
            )
        } bottom: {
            EmptyView()
        }
        .background(theme.surface)
    }

    private var activeAppearance: CardStyleAppearance {
        CardStyleAppearance(style: activeResult?.style ?? .stoic)
    }

    private var answerFace: some View {
        let appearance = activeAppearance

        return cardFace {
            styleSelector(appearance)
        } middle: {
            if let result = activeResult {
                copyBand(
                    Text(result.reframe)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.ink)
                )
            }
        } bottom: {
            recookButton(for: appearance.style, ink: appearance.ink)
        }
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    @ViewBuilder
    private func styleSelector(_ appearance: CardStyleAppearance) -> some View {
        if results.count > 1 {
            StyleChipRow(
                styles: results.map(\.style),
                selected: appearance.style,
                faint: theme.faint
            ) { style in
                selectedStyle = style
            }
        } else {
            stylePill(appearance)
        }
    }

    /// Same three bands as `ReframeCardView`: chrome, flip target, chrome.
    private func cardFace<Top: View, Middle: View, Bottom: View>(
        @ViewBuilder top: () -> Top,
        @ViewBuilder middle: () -> Middle,
        @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                top()

                Spacer(minLength: 0)
                    .allowsHitTesting(false)
            }
            .frame(height: ReframeCardMetrics.topControlHeight)
            .padding(.horizontal, ReframeCardMetrics.chromeInset)
            .padding(.top, ReframeCardMetrics.chromeInset)

            middle()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottom()
                .frame(height: ReframeCardMetrics.contentBottomPad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copyBand(_ copy: Text) -> some View {
        copy
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, ReframeCardMetrics.chromeInset)
            .padding(.top, ReframeCardMetrics.copyTopPad)
            .padding(.bottom, ReframeCardMetrics.copyBottomPad)
            .contentShape(Rectangle())
            .onTapGesture(perform: flip)
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
            .padding(.vertical, 6)
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

    private func flip() {
        flipHaptic += 1

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isFlipped.toggle()
            }
            return
        }

        withAnimation(.timingCurve(0.22, 0.86, 0.28, 1, duration: 0.5)) {
            isFlipped.toggle()
        }
    }

    private func setSelectedStyleWithoutAnimation(_ style: Style?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStyle = style
        }
    }
}

/// Only shown when the cleaned original is in another language than the card copy.
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

/// Selected chip is a labeled pill; the rest stay circles and morph on tap.
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
                                insertion: .opacity.combined(with: .scale(scale: 0.84, anchor: .leading)),
                                removal: .opacity.combined(with: .scale(scale: 0.84, anchor: .leading))
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
