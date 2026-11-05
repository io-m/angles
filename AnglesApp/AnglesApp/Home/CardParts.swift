import SwiftUI

enum ReframeCardMetrics {
    static let overlayMinimumHeight: CGFloat = 300
    static let thoughtFont: Font = .callout.weight(.regular)
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
}

struct OverlayProposalCard: View {
    let thought: String
    var thoughtOriginal: String?
    let results: [ReframeResult]
    var recookingStyle: Style?
    var identityStore: ProfileIdentityStore? = nil
    @Binding var isPublic: Bool
    var showsPrivacyToggle: Bool = true
    var allowsRecook: Bool = true
    var onRecook: (Style) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme

    @State private var showingOriginal = false
    @State private var selectedStyle: Style?
    @State private var recookHaptic = 0
    @State private var privacyHaptic = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    /// The AI's side of compose: the same bubble corner with a small tail at the lower left
    /// as its question and error bubbles (`ComposeLayout.aiCardShape`).
    private var cardShape: UnevenRoundedRectangle {
        ComposeLayout.aiCardShape
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
        if let thoughtOriginal, thoughtOriginal != thought {
            return true
        }
        return results.contains { $0.reframeOriginal != nil }
    }

    private var displayedThought: String {
        showingOriginal ? (thoughtOriginal ?? thought) : thought
    }

    private var displayedAnswer: String? {
        activeResult.map { result in
            showingOriginal ? (result.reframeOriginal ?? result.reframe) : result.reframe
        }
    }

    var body: some View {
        let _ = RenderCounter.hit("OverlayProposalCard")
        VStack(alignment: .leading, spacing: 0) {
            overlayHeader

            ReframeCopyStack(
                thought: displayedThought,
                answer: displayedAnswer,
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
        ViewThatFits(in: .horizontal) {
            overlayHeaderRow

            VStack(alignment: .leading, spacing: 8) {
                AuthorMark(
                    initials: identityStore?.avatarLetters
                        ?? identityStore?.serverInitials
                        ?? UserInitials.letters,
                    avatarPath: identityStore?.avatarPath,
                    prefersLocalPhoto: true,
                    side: ReframeCardMetrics.avatarSize,
                    fill: theme.ink,
                    symbol: theme.paper
                )
                .accessibilityHidden(true)

                HStack(spacing: 8) {
                    overlayPrivacyToggle

                    Spacer(minLength: 4)

                    if hasOriginal {
                        OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                            showingOriginal.toggle()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ReframeCardMetrics.chromeInset)
        .padding(.top, ReframeCardMetrics.chromeInset)
    }

    private var overlayHeaderRow: some View {
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

            if showsPrivacyToggle {
                overlayPrivacyToggle
            }

            if hasOriginal {
                OriginalToggle(showingOriginal: showingOriginal, ink: theme.ink) {
                    showingOriginal.toggle()
                }
            }
        }
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
        guard let result = activeResult, let answer = displayedAnswer else {
            return displayedThought
        }
        return "\(displayedThought). \(result.style.displayName) answer. \(answer)"
    }

    private func setSelectedStyleWithoutAnimation(_ style: Style?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedStyle = style
        }
    }
}

struct ReframeCopyStack: View {
    let thought: String
    let answer: String?
    var answerColor: Color?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(thought)
                .font(ReframeCardMetrics.thoughtFont)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ReframeCardMetrics.chromeInset)
                .padding(.vertical, ReframeCardMetrics.sectionSpacing)
                .contentTransition(.opacity)

            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 1)
                .padding(.horizontal, ReframeCardMetrics.chromeInset)

            if let answer {
                Text(answer)
                    .font(ReframeCardMetrics.answerFont)
                    .foregroundStyle(answerColor ?? theme.ink)
                    .lineSpacing(ReframeCardMetrics.answerLineSpacing)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ReframeCardMetrics.chromeInset)
                    .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 32, height: 32)
                .background(ink.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .accessibilityLabel(showingOriginal ? "Show the English version" : "Show the original wording")
    }
}

/// Selected chip is a labeled pill; the rest stay circles and morph only on a user tap.
struct StyleChipRow: View {
    let styles: [Style]
    let selected: Style
    let faint: Color
    let onSelect: (Style) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectHaptic = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(
                side: ReframeCardMetrics.chipSize,
                showsSelectedLabel: true
            )
            row(
                side: ReframeCardMetrics.chipSizeCompact,
                showsSelectedLabel: true
            )
            row(
                side: ReframeCardMetrics.chipSizeCompact,
                showsSelectedLabel: false
            )
        }
        .sensoryFeedback(.selection, trigger: selectHaptic)
    }

    private func row(
        side: CGFloat,
        showsSelectedLabel: Bool
    ) -> some View {
        HStack(
            spacing: side == ReframeCardMetrics.chipSize
                ? ReframeCardMetrics.chipSpacing
                : 4
        ) {
            ForEach(styles, id: \.self) { style in
                chip(
                    style,
                    side: side,
                    showsSelectedLabel: showsSelectedLabel
                )
            }
        }
    }

    private func chip(
        _ style: Style,
        side: CGFloat,
        showsSelectedLabel: Bool
    ) -> some View {
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

                if isSelected, showsSelectedLabel {
                    Text(style.displayName)
                        .font(
                            side == ReframeCardMetrics.chipSize
                                ? .caption.weight(.semibold)
                                : .caption2.weight(.semibold)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(
                            maxWidth: side == ReframeCardMetrics.chipSize
                                ? nil
                                : 64
                        )
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
            .padding(
                .horizontal,
                isSelected && showsSelectedLabel ? 10 : 0
            )
            .frame(
                width: isSelected && showsSelectedLabel ? nil : side,
                height: side,
                alignment: .center
            )
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
        .accessibilityIdentifier("chip.\(style.rawValue)")
    }
}

/// The six style colours in a row: the Angles mark on sign-in and in the Home header.
struct StyleDotsMark: View {
    var dot: CGFloat = 7
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Style.allCases, id: \.self) { style in
                Circle()
                    .fill(CardStyleAppearance(style: style).ink)
                    .frame(width: dot, height: dot)
            }
        }
    }
}

struct LifeAreaBadge: View {
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

struct StylePill: View {
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

func stylePill(_ appearance: CardStyleAppearance) -> some View {
    StylePill(appearance: appearance)
}

struct FollowBadge: View {
    /// How far the badge hangs off the avatar's bottom-trailing edge.
    static let overhang = CGSize(width: 10, height: 10)

    var following: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pressedScale: CGFloat = 1

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if !reduceMotion {
                pressedScale = 1.38
                Task { @MainActor in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                        pressedScale = 1
                    }
                }
            }
            action()
        } label: {
            Image(systemName: following ? "checkmark" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(following ? theme.paper : theme.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .background {
                    Circle().fill(following ? theme.ink : theme.paper)
                }
                .overlay {
                    Circle().strokeBorder(
                        following ? theme.ink : theme.ink.opacity(theme.isDark ? 0.35 : 0.22),
                        lineWidth: 1
                    )
                }
                .scaleEffect(pressedScale)
                .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.74), value: following)
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(following ? "Unfollow" : "Follow")
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
                RemoteAvatarImage(url: url, side: side)
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
        AvatarLocation.url(for: avatarPath)
    }
}
