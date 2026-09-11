import SwiftUI

enum ReframeCardPresentation: String, Equatable {
    case library
    case pinned
    case favoriteAngles
}

enum ReframeCardMetrics {
    /// Two-column cell on iPhone 14 Pro Max (~193pt) plus chrome (pill, date, heart/pin/menu, initials)
    /// fits max thought (140) and max reframe (190) at the thought type below, with min-scale for Dynamic Type.
    static let baseHeight: CGFloat = 260
    /// Slightly smaller and heavier than `.title3.regular` (20pt); still larger than the answer (`.callout.medium`).
    static let thoughtSize: CGFloat = 18
    static let chromeInset: CGFloat = 16
    static let controlSize: CGFloat = 32

    static var contentBottomPad: CGFloat { chromeInset + controlSize }
}

struct ReframeCardView: View {
    let card: HomeCard
    var presentation: ReframeCardPresentation = .library
    var openingStyle: Style? = nil
    var onDelete: () -> Void = {}
    var onToggleFavorite: (Style) -> Void = { _ in }
    var onTogglePin: () -> Void = {}
    var onSetPublic: (Bool) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = ReframeCardMetrics.baseHeight
    @ScaledMetric(relativeTo: .title3) private var thoughtSize: CGFloat = ReframeCardMetrics.thoughtSize
    @State private var isFlipped = false
    @State private var showingOriginal = false
    @State private var pagedSlideID: UUID?
    @State private var flipHaptic = 0
    @State private var favoriteHaptic = 0
    @State private var pinHaptic = 0
    @State private var showDeleteConfirm = false
    @State private var didSetInitialFace = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var showingThought: Bool {
        isFlipped
    }

    private var visibleSlides: [HomeCardSlide] {
        switch presentation {
        case .library, .pinned:
            return card.slides
        case .favoriteAngles:
            return card.slides.filter(\.isFavorite)
        }
    }

    private var activeSlideIndex: Int {
        guard let pagedSlideID,
              let index = visibleSlides.firstIndex(where: { $0.id == pagedSlideID })
        else {
            return 0
        }

        return index
    }

    var body: some View {
        clippedCard
            .onAppear(perform: syncPresentation)
            .onChange(of: openingStyle) { _, _ in
                syncPager()
            }
            .onChange(of: presentation) { _, _ in
                didSetInitialFace = false
                syncPresentation()
            }
            .onChange(of: visibleSlideIDs) { _, ids in
                if let pagedSlideID, ids.contains(pagedSlideID) {
                    return
                }
                self.pagedSlideID = ids.first
            }
            .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: favoriteHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: pinHaptic)
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

    private var visibleSlideIDs: [UUID] {
        visibleSlides.map(\.id)
    }

    private var accessibilityLabel: String {
        if showingThought {
            return card.thought
        }

        if let slide = visibleSlides[safe: activeSlideIndex] {
            if visibleSlides.count > 1 {
                return "\(slide.result.style.displayName) answer, \(activeSlideIndex + 1) of \(visibleSlides.count). \(slide.result.reframe)"
            }
            return "\(slide.result.style.displayName) answer. \(slide.result.reframe)"
        }

        return card.thought
    }

    private var clippedCard: some View {
        FlipStack(progress: isFlipped ? 1 : 0) {
            answerPager
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
        .overlay(alignment: .topTrailing) {
            ownerMenu
                .padding(ReframeCardMetrics.chromeInset)
        }
        .overlay(alignment: .bottom) {
            bottomChrome
        }
        .overlay(alignment: .bottom) {
            if !showingThought && visibleSlides.count > 1 {
                inCardPageDots
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var thoughtFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            InitialsAvatar(side: ReframeCardMetrics.controlSize, fill: theme.ink, symbol: theme.paper)

            Text(showingOriginal ? (card.thoughtOriginal ?? card.thought) : card.thought)
                .font(.system(size: thoughtSize, weight: .medium))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
        .padding(.bottom, ReframeCardMetrics.contentBottomPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: flip)
    }

    private var hasOriginal: Bool {
        guard let original = card.thoughtOriginal else {
            return false
        }

        return original != card.thought
    }

    private var answerPager: some View {
        Group {
            if visibleSlides.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(visibleSlides) { slide in
                            answerPage(slide.result)
                                .containerRelativeFrame(.horizontal)
                                .id(slide.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pagedSlideID)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else if let slide = visibleSlides.first {
                answerPage(slide.result)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var bottomChrome: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(HomeViewModel.dateLabel(for: card.createdAt))
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .frame(height: ReframeCardMetrics.controlSize, alignment: .leading)
                .onTapGesture(perform: flip)

            Spacer(minLength: 0)
                .allowsHitTesting(false)

            if showingThought {
                pinButton
            } else if let style = visibleSlides[safe: activeSlideIndex]?.result.style {
                favoriteButton(for: style)
            }
        }
        .padding(ReframeCardMetrics.chromeInset)
    }

    private var inCardPageDots: some View {
        let indices = ReframePageDots.visibleIndices(count: visibleSlides.count)
        return HStack(spacing: 3) {
            ForEach(indices, id: \.self) { index in
                let isActive = index == activeSlideIndex
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 10 : 4, height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func answerPage(_ result: ReframeResult) -> some View {
        let appearance = CardStyleAppearance(style: result.style)

        return VStack(alignment: .leading, spacing: 12) {
            stylePill(appearance)
                .onTapGesture(perform: flip)

            Text(result.reframe)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onTapGesture(perform: flip)
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
        .padding(.bottom, ReframeCardMetrics.contentBottomPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    private var ownerMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Card actions")
    }

    private func favoriteButton(for style: Style) -> some View {
        let isFavorite = card.isStyleFavorited(style)
        return Button {
            favoriteHaptic += 1
            onToggleFavorite(style)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isFavorite ? theme.ink : theme.muted)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isFavorite ? "Remove from favorite angles" : "Add to favorite angles"
        )
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }

    private var pinButton: some View {
        Button {
            pinHaptic += 1
            onTogglePin()
        } label: {
            Image(systemName: card.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(card.isPinned ? theme.ink : theme.muted)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.isPinned ? "Unpin this post" : "Pin this post")
        .accessibilityAddTraits(card.isPinned ? .isSelected : [])
    }

    private func syncPresentation() {
        if !didSetInitialFace {
            isFlipped = presentation == .pinned
            didSetInitialFace = true
        }
        syncPager()
    }

    private func syncPager() {
        switch presentation {
        case .favoriteAngles:
            if let preferred = card.latestFavoriteStyle,
               let match = visibleSlides.first(where: { $0.result.style == preferred }) {
                pagedSlideID = match.id
            } else {
                pagedSlideID = visibleSlides.first?.id
            }
        case .library, .pinned:
            pagedSlideID = card.openingSlideID(preferring: openingStyle)
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
    @State private var pagedStyle: Style?
    @State private var flipHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var showingThought: Bool {
        isFlipped
    }

    private var activeIndex: Int {
        guard let pagedStyle,
              let index = results.firstIndex(where: { $0.style == pagedStyle })
        else {
            return 0
        }

        return index
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                FlipStack(progress: isFlipped ? 1 : 0) {
                    answerPager
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

            dots
                .frame(height: 18)
                .opacity(!showingThought && results.count > 1 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if pagedStyle == nil {
                pagedStyle = results.first?.style
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipHaptic)
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

        guard let result = results[safe: activeIndex] else {
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
        VStack(alignment: .leading, spacing: 12) {
            InitialsAvatar(side: ReframeCardMetrics.controlSize, fill: theme.ink, symbol: theme.paper)

            Text(showingOriginal ? (thoughtOriginal ?? thought) : thought)
                .font(.system(size: thoughtSize, weight: .medium))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
        .padding(.bottom, ReframeCardMetrics.contentBottomPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .contentShape(Rectangle())
        .onTapGesture(perform: flip)
    }

    private var answerPager: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(results, id: \.style) { result in
                    answerPage(result)
                        .containerRelativeFrame(.horizontal)
                        .id(result.style)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagedStyle)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .clipped()
    }

    private func answerPage(_ result: ReframeResult) -> some View {
        let appearance = CardStyleAppearance(style: result.style)

        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                stylePill(appearance)
                    .onTapGesture(perform: flip)

                Text(result.reframe)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onTapGesture(perform: flip)
            }
            .padding(.horizontal, ReframeCardMetrics.chromeInset)
            .padding(.top, ReframeCardMetrics.chromeInset)
            .padding(.bottom, ReframeCardMetrics.contentBottomPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            recookButton(for: result.style, ink: appearance.ink)
                .padding(.bottom, ReframeCardMetrics.chromeInset)
                .zIndex(1)
        }
        .background {
            appearance.washFill(over: theme.surface)
        }
    }

    private func recookButton(for style: Style, ink: Color) -> some View {
        let isRecooking = recookingStyle == style
        return Button {
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

    private var dots: some View {
        let indices = ReframePageDots.visibleIndices(count: results.count)
        return HStack(spacing: 5) {
            ForEach(indices, id: \.self) { index in
                let isActive = index == activeIndex
                Capsule()
                    .fill(isActive ? theme.ink : theme.faint)
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
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

/// Only shown when the cleaned original is in another language than the card copy.
private struct OriginalToggle: View {
    let showingOriginal: Bool
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: showingOriginal ? "character.bubble.fill" : "character.bubble")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: ReframeCardMetrics.controlSize, height: ReframeCardMetrics.controlSize)
                .background(ink.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingOriginal ? "Show the English version" : "Show the original wording")
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

enum ReframePageDots {
    static func visibleIndices(count: Int) -> [Int] {
        guard count > 1 else {
            return []
        }

        return Array(0..<count)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
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
                .compositingGroup()
                .opacity(showingBack ? 0 : 1)
                .allowsHitTesting(!showingBack)

            back
                .compositingGroup()
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
