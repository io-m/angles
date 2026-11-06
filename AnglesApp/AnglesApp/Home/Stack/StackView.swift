import SwiftUI

enum StackMetrics {
    /// 16 points a side: the card is about 92% of the screen width.
    static let horizontalInset: CGFloat = 16
    /// How much of each card behind shows under the one in front.
    static let sliver: CGFloat = 10
    /// Front, middle, and the see-through card at the back.
    static let depthCount = 3
    /// Room under the front card for every card behind it.
    static var peek: CGFloat { sliver * CGFloat(depthCount - 1) }
    static let behindScale: CGFloat = 0.94
    static let backScale: CGFloat = 0.88
    /// The back card lets the grey show through. The middle card stays opaque, under a veil.
    static let backOpacity: Double = 0.45
    /// The next card starts smaller than the back slot and scales up into it.
    static let incomingScale: CGFloat = 0.80
    /// The three cards at rest, plus the next one while it scales into the back slot.
    static var renderedCount: Int { depthCount + 1 }
    /// A drag past this commits on release, as does a fast flick.
    static let decideDistance: CGFloat = 110
    static let flickDistance: CGFloat = 240
    /// Below this screen height (iPhone SE, mini) the action row is a size smaller.
    static let compactHeight: CGFloat = 700

    /// The header's full height under the status bar.
    static var headerHeight: CGFloat {
        HeaderCollapse.headerTopPad + HeaderCollapse.headerHeight
    }

    /// The action row's bottom above the screen edge: just over the home indicator, or a
    /// plain margin on a phone with a home button.
    static func barBottom(safeBottom: CGFloat) -> CGFloat {
        safeBottom > 0 ? max(safeBottom - 4, 12) : 16
    }

    /// Button sizes and gap follow dada's action row, a step up from 40/52/72 so the
    /// slightly shorter card still meets a solid row.
    static func inspireSize(screenHeight: CGFloat) -> CGFloat {
        isCompact(screenHeight) ? 64 : 76
    }

    static func decideSize(screenHeight: CGFloat) -> CGFloat {
        isCompact(screenHeight) ? 48 : 56
    }

    static func sideSize(screenHeight: CGFloat) -> CGFloat {
        isCompact(screenHeight) ? 36 : 44
    }

    static func buttonGap(screenWidth: CGFloat) -> CGFloat {
        max(10, screenWidth * 0.053)
    }

    private static func isCompact(_ screenHeight: CGFloat) -> Bool {
        screenHeight > 0 && screenHeight < compactHeight
    }
}

/// Where the card sits between the header and the action row, on any iPhone.
enum StackLayout {
    static let topGap: CGFloat = 15
    static let barGap: CGFloat = 7
    /// Height cap, as a multiple of the 6.1-inch card width. A wider phone wraps the same
    /// answer in fewer lines, so it does not get a taller card.
    static let maxAspect: CGFloat = 1.52
    static let referenceScreenWidth: CGFloat = 393

    /// How far the card and the action row rise together when the phone has spare height.
    static let lift: CGFloat = 16
    /// Extra air under the header, as a share of the screen height, so a shorter phone
    /// keeps the same proportion. Taken from the spare below the card.
    static let headerBreath: CGFloat = 0.003

    struct Frame: Equatable {
        var card: CGSize
        /// Header to card.
        var topGap: CGFloat
        /// The back card's peek to the action row.
        var barGap: CGFloat
        /// Spare taken from under the header and placed under the action row.
        var lift: CGFloat
    }

    static func frame(screen: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> Frame {
        let width = max(0, screen.width - StackMetrics.horizontalInset * 2)
        let header = safeTop + StackMetrics.headerHeight
        let bar = StackMetrics.inspireSize(screenHeight: screen.height) + StackMetrics.barBottom(safeBottom: safeBottom)
        let room = max(0, screen.height - header - bar - topGap - barGap - StackMetrics.peek)
        let referenceWidth = referenceScreenWidth - StackMetrics.horizontalInset * 2
        let height = min(room, min(width, referenceWidth) * maxAspect)
        let spare = room - height
        let half = spare / 2
        let breath = min(half, screen.height * headerBreath)
        let lift = min(Self.lift, half - breath)
        return Frame(
            card: CGSize(width: width, height: height),
            topGap: topGap + half - lift + breath,
            barGap: barGap + half - breath,
            lift: lift
        )
    }
}

/// Where a stack card sits relative to the one in front. Depth 0 is the front card.
/// At `progress == 1` a card matches the resting pose one depth forward, so the swap
/// on release changes nothing on screen by itself.
struct StackCardPose: Equatable {
    var scale: CGFloat
    var offsetY: CGFloat
    var shade: Double
    var opacity: Double

    static func rest(depth: Int, dark: Bool) -> StackCardPose {
        switch max(depth, 0) {
        case 0:
            return StackCardPose(scale: 1, offsetY: 0, shade: 0, opacity: 1)
        case 1:
            return StackCardPose(
                scale: StackMetrics.behindScale,
                offsetY: StackMetrics.sliver,
                shade: dark ? 0.35 : 0.10,
                opacity: 1
            )
        case 2:
            return StackCardPose(
                scale: StackMetrics.backScale,
                offsetY: StackMetrics.sliver * 2,
                shade: 0,
                opacity: StackMetrics.backOpacity
            )
        default:
            return StackCardPose(
                scale: StackMetrics.incomingScale,
                offsetY: StackMetrics.sliver * 2,
                shade: 0,
                opacity: 0
            )
        }
    }

    static func posed(depth: Int, progress: CGFloat, dark: Bool) -> StackCardPose {
        let clamped = max(depth, 0)
        let from = rest(depth: clamped, dark: dark)
        let toward = rest(depth: max(0, clamped - 1), dark: dark)
        let t = min(max(progress, 0), 1)
        let step = Double(t)
        return StackCardPose(
            scale: from.scale + (toward.scale - from.scale) * t,
            offsetY: from.offsetY + (toward.offsetY - from.offsetY) * t,
            shade: from.shade + (toward.shade - from.shade) * step,
            opacity: from.opacity + (toward.opacity - from.opacity) * step
        )
    }
}

/// The top card's drag. Only the views that move with it read it, so a drag frame never
/// redraws the header, the toast, or the rest of the action row.
@MainActor
@Observable
final class StackDrag {
    var offset: CGSize = .zero
    var cardWidth: CGFloat = 0
    /// Only at accessibility sizes, where the card scrolls: set once a drag is known to be
    /// sideways, so a vertical scroll stays a scroll.
    @ObservationIgnored var isDeciding: Bool?
    /// Previous sample's raw translation so each frame adds only its own delta without a startup jump.
    @ObservationIgnored var lastTranslation: CGSize?
    /// Whether the release-threshold haptic has already fired for this touch. Latched so
    /// hovering around the threshold cannot buzz repeatedly; re-armed by `beginTouch()`.
    @ObservationIgnored private(set) var thresholdHapticFired = false
    /// A finger that moves this far is a drag, not a tap on the answer or a style chip.
    static let tapSlop: CGFloat = 12
    /// Set for the rest of this touch once travel passes `tapSlop`. Ignored by observation so a
    /// drag frame does not redraw the card just to suppress its tap.
    @ObservationIgnored var touchWasDrag = false
    /// Bumped when a touch begins, so the clear scheduled by the previous touch cannot land late.
    @ObservationIgnored private var touchGeneration = 0

    /// A new finger-down. Drops the previous touch's drag so the next still tap can change style.
    func beginTouch() {
        touchGeneration += 1
        touchWasDrag = false
        thresholdHapticFired = false
    }

    /// True exactly once per touch: the first time the sideways travel reaches the
    /// release threshold. Retreating and crossing again stays silent until the next touch.
    func noteDecideThreshold(distance: CGFloat) -> Bool {
        guard abs(distance) >= StackMetrics.decideDistance, !thresholdHapticFired else {
            return false
        }
        thresholdHapticFired = true
        return true
    }

    /// `translation` is the finger's travel from the start of the touch, not the card's offset.
    func noteFingerTravel(_ translation: CGSize) {
        if hypot(translation.width, translation.height) > Self.tapSlop {
            touchWasDrag = true
        }
    }

    /// The tap often arrives after the drag ends, so the flag stays set through this turn.
    func finishTouch() {
        guard touchWasDrag else {
            return
        }
        let generation = touchGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.touchGeneration == generation else {
                return
            }
            self.touchWasDrag = false
        }
    }

    /// -1 is a full lean toward Pass, 1 toward Love.
    var lean: CGFloat {
        max(-1, min(1, offset.width / StackMetrics.decideDistance))
    }

    /// Each card behind steps one depth forward as the top card is dragged away.
    var progress: CGFloat {
        guard cardWidth > 0 else {
            return 0
        }
        return min(1, abs(offset.width) / (cardWidth * 0.6))
    }

    /// The leading corner always dips: right turns clockwise, left anticlockwise.
    var tilt: Angle {
        .degrees(Double(offset.width / 22))
    }
}

/// Home: the header, the card stack, the toast slot, and the action row.
struct StackHome: View {
    let viewModel: HomeViewModel
    let safeAreaInsets: EdgeInsets
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?
    var onLogOut: (() -> Void)?
    var onDeleteAccount: (() async -> AccountDeletion)?
    let onInspire: () -> Void
    let onOpenProfile: () -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenFollowed: (FollowedPerson) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var drag = StackDrag()
    @State private var deviceTilt = CardDeviceTilt()
    @State private var flinging: DecisionKind?
    /// Drag haptic: fired once when a drag reaches the release threshold.
    /// Promotion and drag commits stay silent, so a swipe buzzes exactly once.
    @State private var thresholdTick = 0
    /// Button haptic: one light tap when Pass, Love, or Rewind is tapped (the
    /// accessibility Love/Pass actions count as taps too). Navigation buttons
    /// (Inspire, Profile, header) stay silent.
    @State private var actionTick = 0
    @State private var screenSize: CGSize = .zero
    @State private var showFilter = false
    @State private var showSettings = false
    @State private var showPeople = false
    @State private var peopleStartsOnNotifications = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var stack: StackModel { viewModel.stack }
    private var deck: StackDeck { stack.deck }

    var body: some View {
        let _ = RenderCounter.hit("StackHome")
        let layout = StackLayout.frame(
            screen: screenSize,
            safeTop: safeAreaInsets.top,
            safeBottom: safeAreaInsets.bottom
        )
        VStack(spacing: 0) {
            StackHeader(
                filterCount: stack.filter.appliedCount,
                hasUnread: viewModel.unreadFollowCount > 0,
                styleSignal: StyleMarkSignal(
                    cardID: deck.top?.id,
                    style: deck.top.map { deck.style(for: $0) }
                ),
                onFilter: { showFilter = true },
                onNotifications: openNotifications,
                onSettings: { showSettings = true }
            )
            .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)

            cardArea
                .padding(.horizontal, StackMetrics.horizontalInset)
                .overlay(alignment: .bottom) { toast }
                .padding(.top, layout.topGap)
                .zIndex(1)

            StackActionBar(
                screenSize: screenSize,
                canRewind: deck.canRewind && flinging == nil,
                canDecide: deck.top != nil && flinging == nil,
                drag: drag,
                profilePulseToken: viewModel.profilePulseToken,
                onRewind: rewind,
                onPass: { fling(.pass, fromButton: true) },
                onInspire: onInspire,
                onLove: { fling(.save, fromButton: true) },
                onProfile: onOpenProfile
            )
            .padding(.top, layout.barGap)
            .padding(.bottom, StackMetrics.barBottom(safeBottom: safeAreaInsets.bottom) + layout.lift)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(theme.grey.ignoresSafeArea())
        .wideBackSwipe()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: thresholdTick)
        .sensoryFeedback(.impact(weight: .light), trigger: actionTick)
        .onChange(of: stack.visitToken) { _, _ in
            resetDrag()
        }
        .sheet(isPresented: $showFilter) {
            StackFilterSheet(appliedFilter: stack.filter) { next in
                stack.apply(next)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .presentationBackground(theme.grey)
        }
        .modifier(
            AccountSheets(
                showSettings: $showSettings,
                showPeople: $showPeople,
                peopleStartsOnNotifications: peopleStartsOnNotifications,
                viewModel: viewModel,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onLogOut: onLogOut,
                onDeleteAccount: onDeleteAccount,
                onOpenFollowed: onOpenFollowed
            )
        )
        .onChange(of: showPeople) { _, showing in
            if !showing {
                peopleStartsOnNotifications = false
            }
        }
        .onAppear { syncDeviceTilt() }
        .onDisappear { deviceTilt.stop() }
        .onChange(of: scenePhase) { _, _ in syncDeviceTilt() }
        .onChange(of: reduceMotion) { _, _ in syncDeviceTilt() }
    }

    private func syncDeviceTilt() {
        if reduceMotion || scenePhase != .active {
            deviceTilt.stop()
        } else {
            deviceTilt.start()
        }
    }

    private func openNotifications() {
        peopleStartsOnNotifications = true
        showPeople = true
    }

    // MARK: - Cards

    private var cardArea: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - StackMetrics.peek))
            ZStack(alignment: .top) {
                if deck.top != nil {
                    // One view per card, keyed by the card's id: promotion is a role
                    // change on the same face, not a destroy-and-recreate, so its
                    // tilt mark, wash, and state carry across the seam untouched.
                    ForEach(Array(deck.cards.prefix(StackMetrics.renderedCount).enumerated().reversed()), id: \.element.id) { index, card in
                        stackCard(card, depth: index, size: size)
                    }
                } else {
                    placeholder
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .onAppear { drag.cardWidth = size.width }
            .onChange(of: size.width) { _, width in drag.cardWidth = width }
        }
    }

    /// Every depth renders through this one path, and every card gets the live
    /// `deviceTilt`, so a promoted card's watermark and wash are already exactly
    /// where the card in front's would be. Only interaction, elevation, and the
    /// drag-driven motion differ by depth, and at `progress == 1` a card behind
    /// matches the resting pose one depth forward.
    private func stackCard(_ card: HomeCard, depth: Int, size: CGSize) -> some View {
        let isTop = depth == 0
        return StackCardMotion(drag: drag, depth: depth) {
            AngleCardFace(
                card: card,
                sizing: .stack,
                style: Binding(
                    get: { stack.deck.style(for: card) },
                    set: { stack.show($0, on: card.id) }
                ),
                isInteractive: isTop && flinging == nil,
                isElevated: isTop,
                deviceTilt: deviceTilt,
                stackDrag: isTop ? drag : nil,
                actions: actions(for: card)
            )
            .equatable()
            .frame(width: size.width, height: size.height)
        }
        .simultaneousGesture(dragGesture, including: isTop && flinging == nil ? .all : .none)
        .allowsHitTesting(isTop)
        .accessibilityHidden(!isTop)
        .accessibilityAction(named: "Love") { fling(.save, fromButton: true) }
        .accessibilityAction(named: "Pass") { fling(.pass, fromButton: true) }
        .id(card.id)
        .transition(.identity)
    }

    private func actions(for card: HomeCard) -> AngleCardActions {
        var actions = AngleCardActions()
        if !card.isHouse {
            actions.onOpenAuthor = { onOpenAuthor(card) }
        }
        guard !card.isOwner, !card.isHouse, let authorId = card.authorId else {
            return actions
        }
        actions.onReport = { reason in viewModel.reportCard(card.id, reason: reason) }
        actions.onBlock = {
            viewModel.blockAuthor(authorId, initials: card.authorInitials, avatarPath: card.authorAvatarPath)
        }
        actions.onToggleFollow = { viewModel.toggleFollow(authorId) }
        return actions
    }

    @ViewBuilder
    private var placeholder: some View {
        if deck.isFinished {
            StackEndCard(
                filtered: !stack.filter.isEmpty,
                onInspire: onInspire,
                onCheckAgain: stack.startNewVisit,
                onClearFilters: { stack.apply(StackFilter()) }
            )
        } else if stack.loadState == .failed {
            StackMessageCard(
                title: "Couldn't load cards",
                detail: "Check your connection and try again.",
                actionTitle: "Try again",
                action: stack.retry
            )
        } else {
            StackMessageCard(title: nil, detail: nil, actionTitle: nil, action: nil)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toast: some View {
        ZStack {
            if let toast = viewModel.postToast {
                StackToast(toast: toast)
                    .id(toast.token)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.92))
                    )
                    .onTapGesture { viewModel.dismissPostToast() }
            }
        }
        .padding(.bottom, StackMetrics.peek + 14)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82), value: viewModel.postToast)
    }

    // MARK: - Decisions

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1.5, coordinateSpace: .global)
            .onChanged { value in
                if drag.isDeciding == nil, drag.lastTranslation == nil {
                    drag.beginTouch()
                }
                drag.noteFingerTravel(value.translation)
                if drag.isDeciding == nil {
                    drag.isDeciding = dynamicTypeSize.isAccessibilitySize
                        ? abs(value.translation.width) > abs(value.translation.height)
                        : true
                }
                guard drag.isDeciding == true else {
                    return
                }
                guard let previous = drag.lastTranslation else {
                    drag.lastTranslation = value.translation
                    return
                }
                var dx = value.translation.width - previous.width
                var dy = value.translation.height - previous.height
                drag.lastTranslation = value.translation
                if abs(drag.offset.width) < 2, abs(drag.offset.height) < 2 {
                    let step = hypot(dx, dy)
                    if step > 2 {
                        let scale = 1.5 / step
                        dx *= scale
                        dy *= scale
                    }
                }
                let next = CGSize(
                    width: drag.offset.width + dx,
                    height: drag.offset.height + dy
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drag.offset = next
                }
                if drag.noteDecideThreshold(distance: next.width) {
                    thresholdTick &+= 1
                }
            }
            .onEnded { value in
                defer {
                    drag.isDeciding = nil
                    drag.lastTranslation = nil
                    drag.finishTouch()
                }
                guard drag.isDeciding == true else {
                    return
                }
                let distance = drag.offset.width
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let projected = distance + velocity
                if distance > StackMetrics.decideDistance || projected > StackMetrics.flickDistance {
                    fling(.save)
                } else if distance < -StackMetrics.decideDistance || projected < -StackMetrics.flickDistance {
                    fling(.pass)
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.7)) {
                        drag.offset = .zero
                    }
                }
            }
    }

    /// The card leaves first, then the decision commits, so the next card is never drawn mid-flight.
    /// A button-initiated fling buzzes once here; a drag-initiated one already buzzed
    /// at the threshold, and its commit stays silent either way.
    private func fling(_ kind: DecisionKind, fromButton: Bool = false) {
        guard flinging == nil, deck.top != nil else {
            return
        }
        if fromButton {
            actionTick &+= 1
        }
        flinging = kind
        let direction: CGFloat = kind == .save ? 1 : -1
        let distance = max(drag.cardWidth, 320) * 1.5
        let target = CGSize(width: direction * distance, height: drag.offset.height + 40)
        if reduceMotion {
            commit(kind)
            return
        }
        withAnimation(.easeIn(duration: 0.22)) {
            drag.offset = target
        } completion: {
            commit(kind)
        }
    }

    private func commit(_ kind: DecisionKind) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stack.decide(kind)
            drag.offset = .zero
            flinging = nil
        }
    }

    /// The last card comes back in from the side it left by.
    private func rewind() {
        guard flinging == nil else {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        var entrance: CGSize = .zero
        var didRewind = false
        withTransaction(transaction) {
            guard let step = stack.rewind() else {
                return
            }
            didRewind = true
            let direction: CGFloat = step.kind == .save ? 1 : -1
            entrance = CGSize(width: direction * max(drag.cardWidth, 320) * 1.3, height: 30)
            drag.offset = reduceMotion ? .zero : entrance
        }
        if didRewind {
            actionTick &+= 1
        }
        guard !reduceMotion, entrance != .zero else {
            return
        }
        Task { @MainActor [drag] in
            await Task.yield()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                drag.offset = .zero
            }
        }
    }

    private func resetDrag() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag.offset = .zero
            drag.isDeciding = nil
            drag.lastTranslation = nil
            drag.touchWasDrag = false
            flinging = nil
        }
    }
}

// MARK: - Motion

/// One motion wrapper for every depth, so a card keeps the same modifier chain when
/// it is promoted: the only part of Home that redraws per drag frame. The top card
/// follows the finger with its stamps. Each card behind is a step smaller and a
/// sliver lower; the middle one sits under a veil, and the back one is see-through.
/// The next card is hidden until the top card leaves, then scales up into the back
/// slot. At `progress == 1` each card matches the resting pose one depth forward, so
/// promotion changes nothing on screen by itself.
private struct StackCardMotion<Content: View>: View {
    let drag: StackDrag
    let depth: Int
    let content: Content

    init(drag: StackDrag, depth: Int, @ViewBuilder content: () -> Content) {
        self.drag = drag
        self.depth = depth
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isTop = depth == 0
        let pose = StackCardPose.posed(depth: depth, progress: drag.progress, dark: colorScheme == .dark)
        content
            .overlay { StackStamps(lean: isTop ? drag.lean : 0) }
            .overlay {
                RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(pose.shade))
                    .allowsHitTesting(false)
            }
            .opacity(pose.opacity)
            .rotationEffect(isTop ? drag.tilt : .zero, anchor: .bottom)
            .scaleEffect(pose.scale, anchor: .bottom)
            .offset(
                x: isTop ? drag.offset.width : 0,
                y: isTop ? drag.offset.height : pose.offsetY
            )
    }
}

// MARK: - Header

/// Filter on the left, the six style dots in the middle, notifications and Settings on the right.
private struct StackHeader: View {
    let filterCount: Int
    let hasUnread: Bool
    let styleSignal: StyleMarkSignal
    let onFilter: () -> Void
    let onNotifications: () -> Void
    let onSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let _ = RenderCounter.hit("StackHeader")
        ZStack {
            HStack(spacing: 12) {
                Button(action: onFilter) {
                    icon("line.3.horizontal.decrease", weight: .semibold)
                        .overlay(alignment: .topTrailing) {
                            if filterCount > 0 {
                                Text(String(filterCount))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(theme.paper)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .padding(.horizontal, 2)
                                    .background(theme.ink, in: Capsule())
                                    .offset(x: 5, y: -5)
                                    .accessibilityHidden(true)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(filterCount > 0 ? "Filter, \(filterCount) on" : "Filter")
                .accessibilityIdentifier("stack.filter")

                Spacer(minLength: 0)

                Button(action: onNotifications) {
                    icon("bell", weight: .medium)
                        .overlay(alignment: .topTrailing) {
                            if hasUnread {
                                Circle()
                                    .fill(theme.ink)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 1, y: -1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasUnread ? "Notifications, new" : "Notifications")
                .accessibilityIdentifier("stack.notifications")

                Button(action: onSettings) {
                    icon("gearshape", weight: .medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("stack.settings")
            }

            StyleDotsMark(signal: styleSignal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(styleSignal.style.map { "Angles, \($0.displayName)" } ?? "Angles")
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, HeaderCollapse.horizontalPadding)
        .frame(height: HeaderCollapse.headerHeight)
    }

    private func icon(_ systemName: String, weight: Font.Weight) -> some View {
        CircleIcon(
            systemName: systemName,
            fill: theme.surface,
            symbol: theme.ink,
            weight: weight,
            hairline: theme.cardHairline
        )
    }
}

// MARK: - Pieces

/// LOVE in the top-left corner and PASS in the top-right, pressed in as the card leans.
private struct StackStamps: View {
    let lean: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            StackStamp(label: "LOVE", tint: ActionColors.love, angle: -14, presence: max(0, lean))
                .frame(maxWidth: .infinity, alignment: .leading)
            StackStamp(label: "PASS", tint: ActionColors.pass, angle: 14, presence: max(0, -lean))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StackStamp: View {
    let label: String
    let tint: Color
    let angle: Double
    /// 0 is hidden; 1 is fully stamped.
    let presence: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let amount = min(1, presence * 1.4)
        Text(label)
            .font(.system(size: 32, weight: .black))
            .tracking(2)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background {
                shape.fill(theme.surface.opacity(0.7))
                shape.fill(tint.opacity(0.08))
            }
            .overlay(shape.strokeBorder(tint, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .scaleEffect(1.25 - 0.25 * amount)
            .opacity(Double(amount))
    }
}

/// The posted toast: one line in a capsule, ringed once by the arrival glow.
private struct StackToast: View {
    let toast: PostToast

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Label(toast.label, systemImage: toast.label == "Posted" ? "globe" : "lock.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(theme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.cardHairline, lineWidth: 0.5))
            .overlay {
                CardArrivalGlow(
                    tint: CardStyleAppearance(style: toast.tint).ink,
                    prominence: .pill,
                    shape: Capsule()
                )
            }
            .shadow(color: theme.shadowSoft, radius: 12, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A card-shaped frame for loading, an error, and the end of the stack.
private struct StackMessageCard: View {
    let title: String?
    let detail: String?
    let actionTitle: String?
    let action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 14) {
            if let title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.ink)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(StackPillButtonStyle(prominent: true))
                        .padding(.top, 6)
                }
            } else {
                ProgressView()
                    .tint(theme.muted)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        )
    }
}

/// Nothing left from the community or from Angles, or nothing left under the filter.
struct StackEndCard: View {
    var filtered = false
    let onInspire: () -> Void
    let onCheckAgain: () -> Void
    var onClearFilters: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 16) {
            InspireMark(size: 44)
                .padding(.bottom, 4)
            Text(filtered ? "No more cards for these filters" : "You're caught up")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text(filtered ? "Clear the filters to see everything, or write your own." : "Write your own, or check again later for new posts.")
                .font(.callout)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("Inspire me", action: onInspire)
                    .buttonStyle(StackPillButtonStyle(prominent: true))
                if filtered {
                    Button("Clear filters", action: onClearFilters)
                        .buttonStyle(StackPillButtonStyle(prominent: false))
                } else {
                    Button("Check again", action: onCheckAgain)
                        .buttonStyle(StackPillButtonStyle(prominent: false))
                }
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stack.end")
    }
}

private struct StackPillButtonStyle: ButtonStyle {
    let prominent: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? theme.paper : theme.ink)
            .frame(minWidth: 180)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .background(prominent ? theme.ink : theme.ink.opacity(0.06), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - Action row

/// Rewind, Pass, Inspire me, Love, Profile: small, large, largest, large, small.
struct StackActionBar: View {
    let screenSize: CGSize
    let canRewind: Bool
    let canDecide: Bool
    /// Read only by Pass and Love, so a drag frame redraws just those two.
    let drag: StackDrag
    let profilePulseToken: Int
    let onRewind: () -> Void
    let onPass: () -> Void
    let onInspire: () -> Void
    let onLove: () -> Void
    let onProfile: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var gap: CGFloat {
        StackMetrics.buttonGap(screenWidth: screenSize.width)
    }

    var body: some View {
        let _ = RenderCounter.hit("StackActionBar")
        let side = StackMetrics.sideSize(screenHeight: screenSize.height)
        let decide = StackMetrics.decideSize(screenHeight: screenSize.height)
        let inspire = StackMetrics.inspireSize(screenHeight: screenSize.height)
        HStack(spacing: gap) {
            StackRoundButton(side: side, systemImage: "arrow.counterclockwise", iconSize: side * 0.42, tint: theme.ink, action: onRewind)
                .opacity(canRewind ? 1 : 0.5)
                .disabled(!canRewind)
                .accessibilityLabel("Rewind")
                .accessibilityIdentifier("stack.rewind")
            StackDecideButton(drag: drag, towardLove: false, side: decide, systemImage: "xmark", tint: ActionColors.pass, action: onPass)
                .disabled(!canDecide)
                .accessibilityLabel("Pass")
                .accessibilityIdentifier("stack.pass")
            StackInspireButton(side: inspire, action: onInspire)
            StackDecideButton(drag: drag, towardLove: true, side: decide, systemImage: "heart.fill", tint: ActionColors.love, action: onLove)
                .disabled(!canDecide)
                .accessibilityLabel("Love")
                .accessibilityIdentifier("stack.love")
            StackRoundButton(side: side, systemImage: "person.fill", iconSize: side * 0.42, tint: theme.ink, action: onProfile)
                .keyframeAnimator(initialValue: 1.0, trigger: profilePulseToken) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
                }
                .accessibilityLabel("Profile")
                .accessibilityIdentifier("stack.profile")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pass or Love, flooding with its colour as the card leans its way.
private struct StackDecideButton: View {
    let drag: StackDrag
    let towardLove: Bool
    let side: CGFloat
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        let lean = drag.lean
        StackRoundButton(
            side: side,
            systemImage: systemImage,
            iconSize: side * 0.42,
            tint: tint,
            fill: towardLove ? max(0, lean) : max(0, -lean),
            action: action
        )
    }
}

/// A round action on the card surface. `fill` (0–1) floods it with its tint and turns the
/// symbol white, following the card's drag toward that side.
private struct StackRoundButton: View {
    let side: CGFloat
    let systemImage: String
    let iconSize: CGFloat
    let tint: Color
    var fill: CGFloat = 0
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.surface)
                    .shadow(color: theme.shadowSoft, radius: 10, y: 4)
                Circle()
                    .fill(tint)
                    .opacity(fill)
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(tint)
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(theme.surface)
                    .opacity(fill)
            }
            .frame(width: side, height: side)
            .overlay(Circle().strokeBorder(theme.cardHairline, lineWidth: 0.5))
            .scaleEffect(1 + 0.12 * fill)
            .contentShape(Circle())
        }
        .buttonStyle(StackPressStyle())
    }
}

/// Inspire me: the orange mark on the card surface, ringed by a slow, faint orange spark. Its
/// visible size is its real size. Still under Reduce Motion, and stopped while Home is off screen.
private struct StackInspireButton: View {
    let side: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var spinning = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private static let lap: Double = 7

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.surface)
                    .shadow(color: ActionColors.inspire.opacity(0.2), radius: 8, y: 3)
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            stops: [
                                .init(color: ActionColors.inspire.opacity(0.05), location: 0),
                                .init(color: ActionColors.inspire.opacity(0.05), location: 0.45),
                                .init(color: ActionColors.inspire.opacity(0.3), location: 0.8),
                                .init(color: ActionColors.inspire.opacity(0.6), location: 0.98),
                                .init(color: ActionColors.inspire.opacity(0.05), location: 1),
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .animation(spinning ? .linear(duration: Self.lap).repeatForever(autoreverses: false) : nil) {
                        $0.rotationEffect(.degrees(spinning ? 360 : 0))
                    }
                InspireMark(size: side * 0.44)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(StackPressStyle())
        .accessibilityLabel("Inspire me")
        .accessibilityIdentifier("stack.inspire")
        .onAppear { spinning = !reduceMotion }
        .onDisappear { spinning = false }
        .onChange(of: reduceMotion) { _, reduced in spinning = !reduced }
    }
}

private struct StackPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
