import SwiftUI
import UIKit

enum AngleCardSizing: Equatable {
    /// Fills the fixed frame the stack gives it. The answer takes the largest size that fits.
    case stack
    /// Hugs its content, for Profile and author pages.
    case list
}

/// What a card can do. Nil hides the control.
struct AngleCardActions {
    var onDelete: (() -> Void)? = nil
    var onSetPublic: ((Bool) -> Void)? = nil
    var onReport: ((ReportReason) -> Void)? = nil
    var onBlock: (() -> Void)? = nil
    var onOpenAuthor: (() -> Void)? = nil
    var onToggleFollow: (() -> Void)? = nil
    /// The list heart. The stack loves from its action row instead.
    var onToggleSave: (() -> Void)? = nil
}

/// The thought on a stack card: quieter than the answer, and a step smaller when it is long.
enum AngleThoughtSize: Int, CaseIterable, Equatable {
    case body
    case callout
    case subheadline

    static let lineSpacing: CGFloat = 5
    /// Softer than the answer, still easy to read.
    static let inkOpacity: Double = 0.75

    var textStyle: UIFont.TextStyle {
        switch self {
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        }
    }

    var font: Font {
        switch self {
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        }
    }
}

/// One angle's answer size on a stack card, fitted to that answer's own length.
struct AngleAnswerSize: Equatable {
    let pointSize: CGFloat
    /// Even the smallest size does not fit, so the stage scrolls.
    let scrolls: Bool

    var font: Font { .system(size: pointSize, weight: AngleTypeFit.answerWeight) }
    var lineSpacing: CGFloat { AngleTypeFit.lineSpacing(for: pointSize) }
}

enum AngleTypeFit {
    static let largest: CGFloat = 30
    static let smallest: CGFloat = 15
    /// An answer takes at most this share of the space under its tabs.
    static let fill: CGFloat = 0.92
    /// TextKit and SwiftUI round line heights a little differently; this keeps a borderline
    /// answer one size down rather than clipping its last line.
    static let slack: CGFloat = 4
    /// The thought may take this share of the card before it steps down a size.
    static let thoughtShare: CGFloat = 0.3
    static let answerWeight: Font.Weight = .semibold

    private final class Sizes {
        let value: [Style: AngleAnswerSize]

        init(_ value: [Style: AngleAnswerSize]) {
            self.value = value
        }
    }

    private static let cache: NSCache<NSString, Sizes> = {
        let cache = NSCache<NSString, Sizes>()
        cache.countLimit = 64
        return cache
    }()

    /// Every angle's size for one card and box, measured once and then reused.
    static func answerSizes(
        for answers: [Style: String],
        in box: CGSize,
        sizeCategory: UIContentSizeCategory
    ) -> [Style: AngleAnswerSize] {
        let ordered = answers.sorted { $0.key.rawValue < $1.key.rawValue }
        var hasher = Hasher()
        for (style, text) in ordered {
            hasher.combine(style)
            hasher.combine(text)
        }
        let key = "\(hasher.finalize())|\(ordered.count)|\(box.width)x\(box.height)|\(sizeCategory.rawValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        var sizes: [Style: AngleAnswerSize] = [:]
        for (style, text) in ordered {
            sizes[style] = answerSize(for: text, in: box, sizeCategory: sizeCategory)
        }
        // Not laid out yet: nothing worth keeping.
        if box.width > 1, box.height > 1 {
            cache.setObject(Sizes(sizes), forKey: key)
        }
        return sizes
    }

    /// The largest size whose text fills at most `fill` of the box. Below that the smallest size
    /// may use the whole box, and only past it does the stage scroll.
    static func answerSize(
        for answer: String,
        in box: CGSize,
        sizeCategory: UIContentSizeCategory
    ) -> AngleAnswerSize {
        let floor = scaled(smallest, sizeCategory: sizeCategory)
        guard box.width > 1, box.height > 1 else {
            return AngleAnswerSize(pointSize: floor, scrolls: false)
        }
        let target = box.height * fill
        func fits(_ point: CGFloat, within limit: CGFloat) -> Bool {
            answerHeight(answer, pointSize: point, width: box.width) + slack <= limit
        }
        guard fits(floor, within: target) else {
            return AngleAnswerSize(pointSize: floor, scrolls: !fits(floor, within: box.height))
        }
        var low = Int(floor)
        var high = Int(max(floor, scaled(largest, sizeCategory: sizeCategory)))
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(CGFloat(mid), within: target) {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return AngleAnswerSize(pointSize: CGFloat(low), scrolls: false)
    }

    static func answerHeight(_ answer: String, pointSize: CGFloat, width: CGFloat) -> CGFloat {
        height(
            of: answer,
            font: UIFont.systemFont(ofSize: pointSize, weight: .semibold),
            lineSpacing: lineSpacing(for: pointSize),
            width: width
        )
    }

    static func thoughtSize(
        for thought: String,
        width: CGFloat,
        cardHeight: CGFloat,
        sizeCategory: UIContentSizeCategory
    ) -> AngleThoughtSize {
        guard width > 1, cardHeight > 1 else {
            return .body
        }
        for size in AngleThoughtSize.allCases {
            if thoughtHeight(thought, size: size, width: width, sizeCategory: sizeCategory) <= cardHeight * thoughtShare {
                return size
            }
        }
        return .subheadline
    }

    static func thoughtHeight(
        _ thought: String,
        size: AngleThoughtSize,
        width: CGFloat,
        sizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        height(
            of: thought,
            font: uiFont(for: size.textStyle, weight: .regular, sizeCategory: sizeCategory),
            lineSpacing: AngleThoughtSize.lineSpacing,
            width: width
        )
    }

    static func lineSpacing(for pointSize: CGFloat) -> CGFloat {
        (pointSize * 0.18).rounded()
    }

    /// Point sizes are written at the default text size and follow the reader's setting.
    static func scaled(_ points: CGFloat, sizeCategory: UIContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: points, compatibleWith: traits).rounded()
    }

    static func height(of text: String, font: UIFont, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph],
                context: nil
            ).height
        )
    }

    static func uiFont(for style: UIFont.TextStyle, weight: UIFont.Weight, sizeCategory: UIContentSizeCategory) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        return UIFont.systemFont(ofSize: base.pointSize, weight: weight)
    }
}

enum AngleCardMetrics {
    /// List cards.
    static let inset: CGFloat = 16
    static let avatarSize: CGFloat = 36
    static let headerTop: CGFloat = 14
    /// Stack cards: one 18-point inset all round.
    static let stackInset: CGFloat = 18
    static let stackAvatarSize: CGFloat = 40
    static let stackHeaderTop: CGFloat = 16
    static let thoughtTop: CGFloat = 16
    /// Space above the divider, part of the thought's block.
    static let dividerGapAbove: CGFloat = 20
    /// Space below the divider, so the angles sit clear of the larger thought.
    static let dividerGapBelow: CGFloat = 24
    static let dividerHeight: CGFloat = 0.5
    /// The answer hangs this far under its tabs.
    static let answerTop: CGFloat = 12
    static let cornerRadius: CGFloat = 26
    static let watermarkSize: CGFloat = 150

    static func inset(for sizing: AngleCardSizing) -> CGFloat {
        sizing == .stack ? stackInset : inset
    }

    /// Everything on a stack card except the thought's text and the answer: header, gaps,
    /// divider, tabs, and the bottom inset.
    static func stackChrome(thoughtHeight: CGFloat) -> CGFloat {
        stackHeaderTop + headerHeight(for: .stack) + thoughtTop + thoughtHeight
            + dividerGapAbove + dividerHeight + dividerGapBelow
            + ReframeCardMetrics.chipSize + answerTop + stackInset
    }

    static func avatarSize(for sizing: AngleCardSizing) -> CGFloat {
        sizing == .stack ? stackAvatarSize : avatarSize
    }

    /// The header row is as tall as its avatar or its ⋯ button, whichever is taller.
    static func headerHeight(for sizing: AngleCardSizing) -> CGFloat {
        max(avatarSize(for: sizing), ReframeCardMetrics.controlSize)
    }
}

/// The one card face. On the stack: a quiet thought, the style pills, and each answer at the
/// size its own length fills best, over a faded style mark; tap the right half of the answer
/// for the next angle and the left half to go back. In a list those halves cover the thought,
/// divider, and answer, with the pills and the heart underneath.
struct AngleCardFace: View, Equatable {
    let card: HomeCard
    var sizing: AngleCardSizing = .list
    @Binding var style: Style
    /// The card behind the top card: drawn, but not tappable.
    var isInteractive = true
    /// The card behind casts no shadow of its own.
    var isElevated = true
    /// Physical tilt of the phone. Only the top stack card sets this.
    var deviceTilt: CardDeviceTilt?
    /// The stack's drag. Only the top card sets this, and only a tap or chip action reads it,
    /// so a moving finger never redraws the face.
    var stackDrag: StackDrag?
    var actions = AngleCardActions()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingOriginal = false
    @State private var showCardActions = false
    @State private var showDeleteConfirm = false
    @State private var showReportReasons = false
    @State private var showBlockConfirm = false
    @State private var actionsHaptic = 0
    @State private var stepHaptic = 0
    @State private var saveHaptic = 0
    @State private var stageWidth: CGFloat = 0

    static func == (lhs: AngleCardFace, rhs: AngleCardFace) -> Bool {
        lhs.card == rhs.card
            && lhs.sizing == rhs.sizing
            && lhs.style == rhs.style
            && lhs.isInteractive == rhs.isInteractive
            && lhs.isElevated == rhs.isElevated
            && (lhs.actions.onToggleSave == nil) == (rhs.actions.onToggleSave == nil)
            && (lhs.actions.onToggleFollow == nil) == (rhs.actions.onToggleFollow == nil)
    }

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
    }

    private var currentStyle: Style {
        card.hasStyle(style) ? style : card.openingStyle
    }

    private var appearance: CardStyleAppearance {
        CardStyleAppearance(style: currentStyle)
    }

    private var sizeCategory: UIContentSizeCategory {
        UIContentSizeCategory(dynamicTypeSize)
    }

    private var displayedThought: String {
        showingOriginal ? (card.thoughtOriginal ?? card.thought) : card.thought
    }

    private func answer(for style: Style) -> String {
        guard let result = card.slide(for: style)?.result else {
            return ""
        }
        return showingOriginal ? (result.reframeOriginal ?? result.reframe) : result.reframe
    }

    private var hasOriginal: Bool {
        if let original = card.thoughtOriginal, original != card.thought {
            return true
        }
        return card.slides.contains { $0.result.reframeOriginal != nil }
    }

    private var hasMenu: Bool {
        if hasOriginal {
            return true
        }
        if card.isOwner {
            return actions.onDelete != nil || (card.allowsOwnerVisibilityChange && actions.onSetPublic != nil)
        }
        return !card.isHouse && (actions.onReport != nil || actions.onBlock != nil)
    }

    var body: some View {
        let _ = RenderCounter.hit("AngleCardFace")
        Group {
            switch sizing {
            case .stack: stackBody
            case .list: listBody
            }
        }
        .background {
            ZStack {
                appearance.washFill(over: theme.surface)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: currentStyle)
                if sizing == .stack, let deviceTilt, !reduceMotion {
                    CardTiltWash(ink: appearance.ink, tilt: deviceTilt)
                }
            }
        }
        .clipShape(shape)
        .modifier(AngleCardElevation(sizing: sizing, isElevated: isElevated, theme: theme, shape: shape))
        .contentShape(shape)
        .allowsHitTesting(isInteractive)
        .popover(isPresented: $showCardActions, attachmentAnchor: .point(.topTrailing)) {
            cardActionsPanel
                .presentationCompactAdaptation(.popover)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: actionsHaptic)
        .sensoryFeedback(.selection, trigger: stepHaptic)
        .sensoryFeedback(.impact(weight: .light), trigger: saveHaptic)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isInteractive)
        .confirmationDialog("Delete this card?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { actions.onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Why are you reporting this card?",
            isPresented: $showReportReasons,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.displayName, role: .destructive) {
                    actions.onReport?(reason)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block \(displayAuthorInitials)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { actions.onBlock?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their posts will disappear, and you won't be able to follow each other.")
        }
    }

    // MARK: - Stack

    private var scrollsWholeCard: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var inset: CGFloat {
        AngleCardMetrics.inset(for: sizing)
    }

    private var avatarSize: CGFloat {
        AngleCardMetrics.avatarSize(for: sizing)
    }

    private var stackBody: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                header
                moderationNotice
                if scrollsWholeCard {
                    // At accessibility sizes the thought alone can fill a fixed card.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            stackThought(AngleThoughtSize.body.font)
                            thoughtDivider
                            angleTabs
                            answerText(font: .title3.weight(.semibold), lineSpacing: 3, fillsBox: false)
                                .padding(.horizontal, inset)
                                .padding(.top, AngleCardMetrics.answerTop)
                                .padding(.bottom, inset)
                        }
                    }
                    .scrollIndicators(.hidden)
                } else {
                    let thoughtSize = AngleTypeFit.thoughtSize(
                        for: displayedThought,
                        width: proxy.size.width - inset * 2,
                        cardHeight: proxy.size.height,
                        sizeCategory: sizeCategory
                    )
                    stackThought(thoughtSize.font)
                    thoughtDivider
                    angleTabs
                    stage
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func stackThought(_ font: Font) -> some View {
        Text(displayedThought)
            .font(font)
            .foregroundStyle(theme.ink.opacity(AngleThoughtSize.inkOpacity))
            .lineSpacing(AngleThoughtSize.lineSpacing)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, inset)
            .padding(.top, AngleCardMetrics.thoughtTop)
            .contentTransition(.opacity)
    }

    /// The person's thought above, its angles below.
    private var thoughtDivider: some View {
        Rectangle()
            .fill(appearance.ink.opacity(0.15))
            .frame(height: AngleCardMetrics.dividerHeight)
            .padding(.horizontal, inset)
            .padding(.top, AngleCardMetrics.dividerGapAbove)
            .padding(.bottom, AngleCardMetrics.dividerGapBelow)
            .accessibilityHidden(true)
    }

    /// The pills switch the answer right under them; the count says there are more.
    private var angleTabs: some View {
        HStack(spacing: 8) {
            pills
            Spacer(minLength: 4)
            let styles = card.styles
            if styles.count > 1, let index = styles.firstIndex(of: currentStyle) {
                Text("\(index + 1) / \(styles.count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.muted)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, inset)
    }

    private var displayedAnswers: [Style: String] {
        Dictionary(card.styles.map { ($0, answer(for: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    private var stage: some View {
        GeometryReader { proxy in
            let box = CGSize(
                width: max(0, proxy.size.width - inset * 2),
                height: max(0, proxy.size.height - AngleCardMetrics.answerTop - inset)
            )
            let sizes = AngleTypeFit.answerSizes(for: displayedAnswers, in: box, sizeCategory: sizeCategory)
            let fit = sizes[currentStyle]
                ?? AngleTypeFit.answerSize(for: answer(for: currentStyle), in: box, sizeCategory: sizeCategory)
            stageContent(fit)
                .padding(.horizontal, inset)
                .padding(.top, AngleCardMetrics.answerTop)
                .padding(.bottom, inset)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .background(alignment: .bottomTrailing) { watermark }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .gesture(
            SpatialTapGesture().onEnded { tap in
                guard stackDrag?.touchWasDrag != true else {
                    return
                }
                step(forward: tap.location.x >= stageWidth / 2)
            },
            including: isInteractive ? .all : .none
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currentStyle.displayName) answer")
        .accessibilityValue(answer(for: currentStyle))
        .accessibilityHint("Swipe up or down for another angle")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(forward: true)
            case .decrement: step(forward: false)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func stageContent(_ fit: AngleAnswerSize) -> some View {
        if fit.scrolls {
            ScrollView {
                answerText(font: fit.font, lineSpacing: fit.lineSpacing, fillsBox: false)
            }
            .scrollIndicators(.hidden)
        } else {
            answerText(font: fit.font, lineSpacing: fit.lineSpacing, fillsBox: true)
        }
    }

    /// In a fixed box the answer hangs from its tabs and may shrink a hair rather than lose its last line.
    private func answerText(font: Font, lineSpacing: CGFloat, fillsBox: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Text(answer(for: currentStyle))
                .font(font)
                .foregroundStyle(appearance.responseInk)
                .lineSpacing(lineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .minimumScaleFactor(fillsBox ? 0.92 : 1)
                .fixedSize(horizontal: false, vertical: !fillsBox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(currentStyle)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: fillsBox ? .infinity : nil, alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: currentStyle)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showingOriginal)
    }

    /// The style's own mark, large and faint, so a short answer never sits on an empty wash.
    private var watermark: some View {
        CardTiltMark(
            systemImage: appearance.systemImage,
            ink: appearance.ink,
            tilt: sizing == .stack ? deviceTilt : nil
        )
        .id(currentStyle)
        .transition(.opacity)
    }

    // MARK: - List

    private var listBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            moderationNotice
            listCopy
            listFooter
            ownerLoves
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Thought, divider, and answer. A still finger on the right half steps forward and the
    /// left half steps back; a moving finger still scrolls the sheet.
    private var listCopy: some View {
        ReframeCopyStack(
            thought: displayedThought,
            answer: answer(for: currentStyle),
            answerColor: appearance.responseInk
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stageWidth = $0 }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { tap in
                step(forward: tap.location.x >= stageWidth / 2)
            },
            including: isInteractive ? .all : .none
        )
        .accessibilityAction(named: "Next angle") { step(forward: true) }
        .accessibilityAction(named: "Previous angle") { step(forward: false) }
    }

    private var listFooter: some View {
        HStack(spacing: 10) {
            pills
            Spacer(minLength: 8)
            if let onToggleSave = actions.onToggleSave, card.isDecidable {
                loveToggle(onToggleSave)
            }
        }
        .padding(.horizontal, AngleCardMetrics.inset)
        .padding(.top, 12)
        .padding(.bottom, hasOwnerLoves ? 6 : AngleCardMetrics.inset)
    }

    private func loveToggle(_ action: @escaping () -> Void) -> some View {
        Button {
            saveHaptic += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.58)) {
                action()
            }
        } label: {
            Image(systemName: card.isSaved ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(card.isSaved ? ActionColors.love : theme.muted)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.4), value: saveHaptic)
                .frame(width: 40, height: ReframeCardMetrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.isSaved ? "Remove from Loved" : "Love")
        .accessibilityAddTraits(card.isSaved ? .isSelected : [])
    }

    private var hasOwnerLoves: Bool {
        card.isOwner && (card.saveCount ?? 0) > 0
    }

    @ViewBuilder
    private var ownerLoves: some View {
        if hasOwnerLoves, let total = card.saveCount {
            let onAngle = card.slide(for: currentStyle)?.saveCount ?? 0
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption.weight(.semibold))
                Text(ownerLovesText(total: total, onAngle: onAngle))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(appearance.ink.opacity(0.85))
            .padding(.horizontal, AngleCardMetrics.inset)
            .padding(.bottom, AngleCardMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func ownerLovesText(total: Int, onAngle: Int) -> String {
        let people = total == 1 ? "1 love" : "\(total.formatted()) loves"
        guard onAngle > 0 else {
            return people
        }
        return "\(people) · \(onAngle.formatted()) on \(currentStyle.displayName)"
    }

    // MARK: - Shared chrome

    @ViewBuilder
    private var pills: some View {
        if card.styles.count > 1 {
            StyleChipRow(styles: card.styles, selected: currentStyle, faint: theme.faint) { next in
                guard stackDrag?.touchWasDrag != true else {
                    return
                }
                style = next
            }
        } else {
            stylePill(appearance)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if card.isHouse {
                InspireMark(size: avatarSize * 0.5)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(theme.paper, in: Circle())
                    .overlay { Circle().strokeBorder(theme.cardHairline, lineWidth: 0.5) }
                    .accessibilityHidden(true)
                Text("From Angles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                authorControl
                Text(HomeViewModel.dateLabel(for: card.createdAt))
                    .font(sizing == .stack ? .footnote.weight(.medium) : .caption.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .fixedSize()
                if card.isOwner, card.isPublic {
                    Image(systemName: "globe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.muted)
                        .accessibilityLabel("Public")
                }
            }

            Spacer(minLength: 4)

            if let lifeArea = card.lifeAreaPresentation {
                LifeAreaBadge(
                    category: lifeArea.category,
                    label: lifeArea.label,
                    maxWidth: ReframeCardMetrics.lifeAreaBadgeStripMaxWidth,
                    iconSize: sizing == .stack ? 15 : 12,
                    labelFont: sizing == .stack ? .subheadline.weight(.medium) : .caption.weight(.medium)
                )
            }

            if hasMenu {
                Button {
                    actionsHaptic += 1
                    showCardActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 28, height: ReframeCardMetrics.controlSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card actions")
            }
        }
        .frame(minHeight: avatarSize)
        .padding(.horizontal, inset)
        .padding(.top, sizing == .stack ? AngleCardMetrics.stackHeaderTop : AngleCardMetrics.headerTop)
    }

    @ViewBuilder
    private var authorControl: some View {
        ZStack(alignment: .bottomTrailing) {
            if let onOpenAuthor = actions.onOpenAuthor, card.authorId != nil {
                Button(action: onOpenAuthor) {
                    authorMark
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Posts by \(card.authorInitials)")
            } else {
                authorMark
            }

            if !card.isOwner, card.authorId != nil, let onToggleFollow = actions.onToggleFollow {
                FollowBadge(following: card.authorFollowing, action: onToggleFollow)
                    .offset(FollowBadge.overhang)
            }
        }
    }

    private var authorMark: some View {
        AuthorMark(
            initials: card.authorInitials,
            avatarPath: card.authorAvatarPath,
            prefersLocalPhoto: card.isOwner,
            side: avatarSize,
            fill: theme.ink,
            symbol: theme.paper
        )
    }

    @ViewBuilder
    private var moderationNotice: some View {
        if let notice = card.moderationNoticeText {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption.weight(.semibold))
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, inset)
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Moving between angles

    private func select(_ next: Style) {
        guard next != currentStyle else {
            return
        }
        stepHaptic += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78)) {
            style = next
        }
    }

    private func step(forward: Bool) {
        let styles = card.styles
        guard styles.count > 1, let index = styles.firstIndex(of: currentStyle) else {
            return
        }
        if forward {
            select(styles[(index + 1) % styles.count])
        } else if index > 0 {
            select(styles[index - 1])
        }
    }

    // MARK: - Actions

    private var cardActionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasOriginal {
                actionRow(
                    showingOriginal ? "Show English" : "Show original",
                    systemImage: showingOriginal ? "character.bubble.fill" : "character.bubble"
                ) {
                    showCardActions = false
                    showingOriginal.toggle()
                }
                if card.isOwner || !card.isHouse {
                    divider
                }
            }

            if card.isOwner {
                if card.allowsOwnerVisibilityChange, let onSetPublic = actions.onSetPublic {
                    actionRow(
                        card.isPublic ? "Make private" : "Make public",
                        systemImage: card.isPublic ? "lock.fill" : "globe"
                    ) {
                        let makePublic = !card.isPublic
                        runAfterActionsClose { onSetPublic(makePublic) }
                    }
                    divider
                }
                if actions.onDelete != nil {
                    actionRow("Delete", systemImage: "trash", color: Self.blockRed) {
                        runAfterActionsClose { showDeleteConfirm = true }
                    }
                }
            } else if !card.isHouse {
                if let onToggleFollow = actions.onToggleFollow, card.authorId != nil {
                    actionRow(
                        card.authorFollowing ? "Unfollow \(displayAuthorInitials)" : "Follow \(displayAuthorInitials)",
                        systemImage: card.authorFollowing ? "person.badge.minus" : "person.badge.plus"
                    ) {
                        runAfterActionsClose(onToggleFollow)
                    }
                    divider
                }
                if actions.onReport != nil {
                    actionRow("Report", systemImage: "exclamationmark.bubble", color: Self.reportRedOrange) {
                        runAfterActionsClose { showReportReasons = true }
                    }
                    divider
                }
                if actions.onBlock != nil {
                    actionRow("Block \(displayAuthorInitials)", systemImage: "hand.raised", color: Self.blockRed) {
                        runAfterActionsClose { showBlockConfirm = true }
                    }
                }
            }
        }
        .frame(minWidth: 232)
        .padding(.vertical, 6)
    }

    private var displayAuthorInitials: String {
        let trimmed = card.authorInitials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this person" : trimmed
    }

    /// Report is red-orange; block and delete stay red so the two read apart.
    private static let reportRedOrange = Color(red: 0.96, green: 0.36, blue: 0.14)
    private static let blockRed = Color(uiColor: .systemRed)

    private func actionRow(
        _ title: String,
        systemImage: String,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(title)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .frame(width: 22)
            }
            .foregroundStyle(color ?? theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.cardHairline)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    /// A confirmation sheet cannot present while this popover is still up.
    private func runAfterActionsClose(_ action: @escaping () -> Void) {
        showCardActions = false
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}

/// List cards keep the composited glow. A stack card casts its shadow from a plain shape behind
/// it, so moving it never re-renders its text for the shadow.
private struct AngleCardElevation: ViewModifier {
    let sizing: AngleCardSizing
    let isElevated: Bool
    let theme: ColorTokens.Theme
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch sizing {
        case .list:
            ReframeCardElevation.chrome(on: content, theme: theme, shape: shape)
        case .stack:
            content
                .overlay {
                    shape.strokeBorder(theme.cardHairline, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
                .background {
                    if isElevated {
                        shape.fill(theme.surface)
                            .shadow(color: theme.cardAmbientShadow, radius: theme.isDark ? 22 : 26)
                            .shadow(color: theme.cardAmbientCore, radius: theme.isDark ? 11 : 13)
                    }
                }
        }
    }
}

extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        @unknown default: self = .large
        }
    }
}
