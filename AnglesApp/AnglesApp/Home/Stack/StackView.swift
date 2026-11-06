import SwiftUI
import UIKit

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
    static let behindShadeDark: Double = 0.24
    static let behindShadeLight: Double = 0.14
    static let backShadeDark: Double = 0.30
    static let backShadeLight: Double = 0.18
    /// The back card lets the grey show through. The middle card stays opaque, under a veil.
    static let backOpacityLight: Double = 0.38
    static let backOpacityDark: Double = 0.58

    static func backOpacity(dark: Bool) -> Double {
        dark ? backOpacityDark : backOpacityLight
    }
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
                shade: dark ? StackMetrics.behindShadeDark : StackMetrics.behindShadeLight,
                opacity: 1
            )
        case 2:
            return StackCardPose(
                scale: StackMetrics.backScale,
                offsetY: StackMetrics.sliver * 2,
                shade: dark ? StackMetrics.backShadeDark : StackMetrics.backShadeLight,
                opacity: StackMetrics.backOpacity(dark: dark)
            )
        default:
            return StackCardPose(
                scale: StackMetrics.incomingScale,
                offsetY: StackMetrics.sliver * 2,
                shade: dark ? StackMetrics.backShadeDark : StackMetrics.backShadeLight,
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

/// The top card's drag. Granular properties (`progress`, `loveFill`, `passFill`) are updated
/// only when their values change, so a rightward drag never redraws Pass, a vertical drag
/// never redraws the cards behind, and haptics fire from an empty observer view.
@MainActor
@Observable
final class StackDrag {
    var offset: CGSize = .zero {
        didSet {
            syncDerivedMetrics()
        }
    }
    var cardWidth: CGFloat = 0 {
        didSet {
            syncDerivedMetrics()
        }
    }
    /// Each card behind steps one depth forward as the top card is dragged away.
    private(set) var progress: CGFloat = 0
    /// 0...1 fill toward Love (rightward drag).
    private(set) var loveFill: CGFloat = 0
    /// 0...1 fill toward Pass (leftward drag).
    private(set) var passFill: CGFloat = 0
    /// True while the card is displaced from rest.
    private(set) var isMoving = false
    /// Drag haptic: fired once when a drag reaches the release threshold.
    private(set) var thresholdTick = 0
    /// Button haptic: one light tap when Pass, Love, or Rewind is tapped.
    private(set) var actionTick = 0

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
    @discardableResult
    func noteDecideThreshold(distance: CGFloat) -> Bool {
        guard abs(distance) >= StackMetrics.decideDistance, !thresholdHapticFired else {
            return false
        }
        thresholdHapticFired = true
        thresholdTick &+= 1
        return true
    }

    func fireActionHaptic() {
        actionTick &+= 1
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

    /// The leading corner always dips: right turns clockwise, left anticlockwise.
    var tilt: Angle {
        .degrees(Double(offset.width / 22))
    }

    private func syncDerivedMetrics() {
        let rawLean = max(-1, min(1, offset.width / StackMetrics.decideDistance))
        let nextLove = max(0, rawLean)
        if loveFill != nextLove {
            loveFill = nextLove
        }
        let nextPass = max(0, -rawLean)
        if passFill != nextPass {
            passFill = nextPass
        }
        let nextProgress: CGFloat = cardWidth > 0 ? min(1, abs(offset.width) / (cardWidth * 0.6)) : 0
        if progress != nextProgress {
            progress = nextProgress
        }
        let nextMoving = offset != .zero
        if isMoving != nextMoving {
            isMoving = nextMoving
        }
    }
}

/// Ephemeral UI state for Home (active fling and modal sheets), isolated from `StackHome.body`
/// so presenting a sheet or starting a fling only updates the subviews that care.
@MainActor
@Observable
final class StackScreenState {
    var flinging: DecisionKind?
    var showFilter = false
    var showSettings = false
    var showPeople = false
    @ObservationIgnored var peopleStartsOnNotifications = false

    var hasPresentedSheet: Bool {
        showFilter || showSettings || showPeople
    }

    func openNotifications() {
        peopleStartsOnNotifications = true
        showPeople = true
    }

    func dismissSheets() {
        showFilter = false
        showSettings = false
        showPeople = false
        peopleStartsOnNotifications = false
    }
}

/// Home: the header, the card stack, the toast slot, and the action row.
/// `StackHome.body` reads only `screenSize`, `safeAreaInsets`, and `colorScheme`; every
/// dynamic signal is observed inside its own leaf container.
struct StackHome: View {
    let viewModel: HomeViewModel
    let safeAreaInsets: EdgeInsets
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?
    var screenState: StackScreenState
    var onLogOut: (() -> Void)?
    var onDeleteAccount: (() async -> AccountDeletion)?
    let onInspire: () -> Void
    let onOpenProfile: () -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onOpenFollowed: (FollowedPerson) -> Void
    var onOpenPost: (PostRoute) -> Void = { _ in }
    var onSheetDismissed: () -> Void = {}
    var isHomeActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var drag = StackDrag()
    @State private var deviceTilt = CardDeviceTilt()
    @State private var screenSize: CGSize = .zero

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var stack: StackModel { viewModel.stack }

    var body: some View {
        let _ = RenderCounter.hit("StackHome")
        let layout = StackLayout.frame(
            screen: screenSize,
            safeTop: safeAreaInsets.top,
            safeBottom: safeAreaInsets.bottom
        )
        VStack(spacing: 0) {
            StackHeaderContainer(
                viewModel: viewModel,
                screenState: screenState
            )
            .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)

            StackStageView(
                viewModel: viewModel,
                drag: drag,
                deviceTilt: deviceTilt,
                screenState: screenState,
                onInspire: onInspire,
                onOpenAuthor: onOpenAuthor,
                onFling: fling
            )
            .padding(.horizontal, StackMetrics.horizontalInset)
            .overlay(alignment: .bottom) {
                StackToastOverlay(viewModel: viewModel)
            }
            .padding(.top, layout.topGap)
            .zIndex(1)

            StackActionBar(
                viewModel: viewModel,
                drag: drag,
                screenState: screenState,
                screenSize: screenSize,
                isHomeActive: isHomeActive,
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
        .background {
            StackSessionEffects(
                stack: stack,
                drag: drag,
                deviceTilt: deviceTilt,
                screenState: screenState,
                isHomeActive: isHomeActive,
                onResetDrag: resetDrag
            )
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { nextSize in
            if screenSize != nextSize {
                screenSize = nextSize
            }
        }
        .modifier(
            StackSheetsModifier(
                screenState: screenState,
                viewModel: viewModel,
                storeKitManager: storeKitManager,
                identityStore: identityStore,
                onLogOut: onLogOut,
                onDeleteAccount: onDeleteAccount,
                onOpenFollowed: onOpenFollowed,
                onOpenPost: onOpenPost,
                onSheetDismissed: onSheetDismissed
            )
        )
    }

    // MARK: - Decisions

    /// The card leaves first, then the decision commits, so the next card is never drawn mid-flight.
    /// A button-initiated fling buzzes once here; a drag-initiated one already buzzed
    /// at the threshold, and its commit stays silent either way.
    private func fling(_ kind: DecisionKind, fromButton: Bool = false) {
        guard screenState.flinging == nil, stack.hasTopCard else {
            return
        }
        if fromButton {
            drag.fireActionHaptic()
        }
        screenState.flinging = kind
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
            screenState.flinging = nil
        }
    }

    /// The last card comes back in from the side it left by.
    private func rewind() {
        guard screenState.flinging == nil else {
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
            drag.fireActionHaptic()
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
            screenState.flinging = nil
        }
    }
}

// MARK: - Isolated Subtrees

private struct StackHeaderContainer: View {
    let viewModel: HomeViewModel
    let screenState: StackScreenState

    var body: some View {
        let stack = viewModel.stack
        StackHeader(
            filterCount: stack.filter.appliedCount,
            hasUnread: viewModel.unreadNotificationCount > 0,
            styleSignal: stack.topStyleSignal,
            onFilter: { screenState.showFilter = true },
            onNotifications: { screenState.openNotifications() },
            onSettings: { screenState.showSettings = true }
        )
    }
}

private struct StackStageView: View {
    let viewModel: HomeViewModel
    let drag: StackDrag
    let deviceTilt: CardDeviceTilt
    let screenState: StackScreenState
    let onInspire: () -> Void
    let onOpenAuthor: (HomeCard) -> Void
    let onFling: (DecisionKind, Bool) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stack: StackModel { viewModel.stack }

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(
                width: proxy.size.width,
                height: max(0, proxy.size.height - StackMetrics.peek)
            )
            ZStack(alignment: .top) {
                if stack.hasTopCard {
                    let cards = stack.renderedCards
                    let isIdle = screenState.flinging == nil
                    // One view per card, keyed by the card's id: promotion is a role
                    // change on the same face, not a destroy-and-recreate, so its
                    // tilt mark, wash, and state carry across the seam untouched.
                    ForEach(Array(cards.enumerated().reversed()), id: \.element.id) { index, card in
                        stackCard(card, depth: index, size: size, isIdle: isIdle)
                    }
                } else {
                    StackPlaceholderView(stack: stack, onInspire: onInspire)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .onAppear {
                if drag.cardWidth != size.width {
                    drag.cardWidth = size.width
                }
            }
            .onChange(of: size.width) { _, width in
                if drag.cardWidth != width {
                    drag.cardWidth = width
                }
            }
        }
    }

    private func stackCard(_ card: HomeCard, depth: Int, size: CGSize, isIdle: Bool) -> some View {
        let isTop = depth == 0
        let isInteractive = isTop && isIdle
        return StackCardMotion(drag: drag, depth: depth) {
            AngleCardFace(
                card: card,
                sizing: .stack,
                style: stack.style(for: card),
                stackCardSize: size,
                isInteractive: isInteractive,
                isElevated: isTop,
                deviceTilt: deviceTilt,
                stackDrag: isTop ? drag : nil,
                actions: actions(for: card),
                onSelectStyle: { stack.show($0, on: card.id) }
            )
            .equatable()
            .frame(width: size.width, height: size.height)
        }
        .simultaneousGesture(dragGesture, including: isInteractive ? .all : .none)
        .allowsHitTesting(isTop)
        .accessibilityHidden(!isTop)
        .accessibilityAction(named: "Love") { onFling(.save, true) }
        .accessibilityAction(named: "Pass") { onFling(.pass, true) }
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
                _ = drag.noteDecideThreshold(distance: next.width)
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
                    onFling(.save, false)
                } else if distance < -StackMetrics.decideDistance || projected < -StackMetrics.flickDistance {
                    onFling(.pass, false)
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.7)) {
                        drag.offset = .zero
                    }
                }
            }
    }
}

/// Only mounted when the deck has no top card, so background page prefetches that toggle
/// `stack.loadState` never invalidate the stage while cards are on screen.
private struct StackPlaceholderView: View {
    let stack: StackModel
    let onInspire: () -> Void

    var body: some View {
        if stack.isFinished {
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
}

private struct StackToastOverlay: View {
    let viewModel: HomeViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let toast = viewModel.postToast
        ZStack {
            if let toast {
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
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82),
            value: toast
        )
    }
}

/// Zero-size observer for haptics, visit resets, layout prewarming, and CoreMotion lifecycle.
private struct StackSessionEffects: View {
    let stack: StackModel
    let drag: StackDrag
    let deviceTilt: CardDeviceTilt
    let screenState: StackScreenState
    let isHomeActive: Bool
    let onResetDrag: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var shouldRunTilt: Bool {
        isHomeActive
            && !screenState.hasPresentedSheet
            && stack.hasTopCard
            && !reduceMotion
            && scenePhase == .active
    }

    private var shouldPauseTilt: Bool {
        drag.isMoving || screenState.flinging != nil
    }

    var body: some View {
        Color.clear
            .sensoryFeedback(.impact(weight: .light), trigger: drag.thresholdTick)
            .sensoryFeedback(.impact(weight: .light), trigger: drag.actionTick)
            .onAppear {
                syncTilt()
                deviceTilt.isPaused = shouldPauseTilt
            }
            .onDisappear {
                deviceTilt.stop()
            }
            .onChange(of: stack.visitToken) { _, _ in
                onResetDrag()
            }
            .onChange(of: shouldRunTilt) { _, _ in
                syncTilt()
            }
            .onChange(of: shouldPauseTilt) { _, paused in
                deviceTilt.isPaused = paused
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func syncTilt() {
        if shouldRunTilt {
            deviceTilt.start()
        } else {
            deviceTilt.stop()
        }
    }
}

private struct StackSheetsModifier: ViewModifier {
    @Bindable var screenState: StackScreenState
    let viewModel: HomeViewModel
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?
    var onLogOut: (() -> Void)?
    var onDeleteAccount: (() async -> AccountDeletion)?
    let onOpenFollowed: (FollowedPerson) -> Void
    let onOpenPost: (PostRoute) -> Void
    let onSheetDismissed: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $screenState.showFilter, onDismiss: onSheetDismissed) {
                StackFilterSheet(appliedFilter: viewModel.stack.filter) { next in
                    viewModel.stack.apply(next)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(theme.grey)
            }
            .modifier(
                AccountSheets(
                    showSettings: $screenState.showSettings,
                    showPeople: $screenState.showPeople,
                    peopleStartsOnNotifications: screenState.peopleStartsOnNotifications,
                    viewModel: viewModel,
                    storeKitManager: storeKitManager,
                    identityStore: identityStore,
                    onLogOut: onLogOut,
                    onDeleteAccount: onDeleteAccount,
                    onOpenFollowed: onOpenFollowed,
                    onOpenPost: onOpenPost,
                    onSheetDismissed: onSheetDismissed
                )
            )
            .onChange(of: screenState.showPeople) { _, showing in
                if !showing {
                    screenState.peopleStartsOnNotifications = false
                }
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
        let dark = colorScheme == .dark
        let pose = isTop
            ? StackCardPose.rest(depth: 0, dark: dark)
            : StackCardPose.posed(depth: depth, progress: drag.progress, dark: dark)
        let topOffset: CGSize = isTop ? drag.offset : .zero
        let topTilt: Angle = isTop ? drag.tilt : .zero
        content
            .overlay { StackStamps(drag: isTop ? drag : nil) }
            .overlay {
                RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(pose.shade))
                    .allowsHitTesting(false)
            }
            .opacity(pose.opacity)
            .rotationEffect(topTilt, anchor: .bottom)
            .scaleEffect(pose.scale, anchor: .bottom)
            .offset(
                x: topOffset.width,
                y: isTop ? topOffset.height : pose.offsetY
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
/// Only the top card passes a non-nil `drag`, and each stamp observes only its own side's fill.
private struct StackStamps: View {
    let drag: StackDrag?

    var body: some View {
        if let drag {
            ZStack(alignment: .top) {
                StackLoveStamp(drag: drag)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StackPassStamp(drag: drag)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct StackLoveStamp: View {
    let drag: StackDrag

    var body: some View {
        let presence = drag.loveFill
        if presence > 0 {
            StackStamp(label: "LOVE", tint: ActionColors.love, angle: -14, presence: presence)
        }
    }
}

private struct StackPassStamp: View {
    let drag: StackDrag

    var body: some View {
        let presence = drag.passFill
        if presence > 0 {
            StackStamp(label: "PASS", tint: ActionColors.pass, angle: 14, presence: presence)
        }
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
        VStack(spacing: 2) {
            Label(toast.label, systemImage: toast.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
            if let detail = toast.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(theme.muted)
            }
        }
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
/// Each button observes only its own signal so `StackActionBar.body` never redraws during swipes.
struct StackActionBar: View {
    let viewModel: HomeViewModel
    let drag: StackDrag
    let screenState: StackScreenState
    let screenSize: CGSize
    var isHomeActive: Bool = true
    let onRewind: () -> Void
    let onPass: () -> Void
    let onInspire: () -> Void
    let onLove: () -> Void
    let onProfile: () -> Void

    private var gap: CGFloat {
        StackMetrics.buttonGap(screenWidth: screenSize.width)
    }

    var body: some View {
        let _ = RenderCounter.hit("StackActionBar")
        let side = StackMetrics.sideSize(screenHeight: screenSize.height)
        let decide = StackMetrics.decideSize(screenHeight: screenSize.height)
        let inspire = StackMetrics.inspireSize(screenHeight: screenSize.height)
        HStack(spacing: gap) {
            StackRewindButton(
                stack: viewModel.stack,
                screenState: screenState,
                side: side,
                action: onRewind
            )
            StackDecideButton(
                stack: viewModel.stack,
                screenState: screenState,
                drag: drag,
                towardLove: false,
                side: decide,
                systemImage: "xmark",
                tint: ActionColors.pass,
                action: onPass
            )
            .accessibilityLabel("Pass")
            .accessibilityIdentifier("stack.pass")
            StackInspireButton(
                side: inspire,
                screenState: screenState,
                isHomeActive: isHomeActive,
                action: onInspire
            )
            StackDecideButton(
                stack: viewModel.stack,
                screenState: screenState,
                drag: drag,
                towardLove: true,
                side: decide,
                systemImage: "heart.fill",
                tint: ActionColors.love,
                action: onLove
            )
            .accessibilityLabel("Love")
            .accessibilityIdentifier("stack.love")
            StackProfileButton(
                viewModel: viewModel,
                side: side,
                action: onProfile
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StackRewindButton: View {
    let stack: StackModel
    let screenState: StackScreenState
    let side: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let canRewind = stack.canRewind && screenState.flinging == nil
        StackRoundButton(
            side: side,
            systemImage: "arrow.counterclockwise",
            iconSize: side * 0.42,
            tint: theme.ink,
            action: action
        )
        .opacity(canRewind ? 1 : 0.5)
        .disabled(!canRewind)
        .accessibilityLabel("Rewind")
        .accessibilityIdentifier("stack.rewind")
    }
}

private struct StackProfileButton: View {
    let viewModel: HomeViewModel
    let side: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        StackRoundButton(
            side: side,
            systemImage: "person.fill",
            iconSize: side * 0.42,
            tint: theme.ink,
            action: action
        )
        .keyframeAnimator(initialValue: 1.0, trigger: viewModel.profilePulseToken) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.32, spring: .bouncy)
        }
        .accessibilityLabel("Profile")
        .accessibilityIdentifier("stack.profile")
    }
}

/// Pass or Love, flooding with its colour only when the card leans toward its side.
private struct StackDecideButton: View {
    let stack: StackModel
    let screenState: StackScreenState
    let drag: StackDrag
    let towardLove: Bool
    let side: CGFloat
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        let canDecide = stack.hasTopCard && screenState.flinging == nil
        let fill = towardLove ? drag.loveFill : drag.passFill
        StackRoundButton(
            side: side,
            systemImage: systemImage,
            iconSize: side * 0.42,
            tint: tint,
            fill: fill,
            action: action
        )
        .disabled(!canDecide)
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
                if fill > 0 {
                    Circle()
                        .fill(tint)
                        .opacity(fill)
                }
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(tint)
                if fill > 0 {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(theme.surface)
                        .opacity(fill)
                }
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
/// visible size is its real size. Still under Reduce Motion, and stopped while Home is covered or off screen.
private struct StackInspireButton: View {
    let side: CGFloat
    let screenState: StackScreenState
    let isHomeActive: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var shouldSpin: Bool {
        isHomeActive && !screenState.hasPresentedSheet && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.surface)
                    .shadow(color: ActionColors.inspire.opacity(0.2), radius: 8, y: 3)
                InspireSparkRing(isSpinning: shouldSpin)
                InspireMark(size: side * 0.44)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
        }
        .buttonStyle(StackPressStyle())
        .accessibilityLabel("Inspire me")
        .accessibilityIdentifier("stack.inspire")
    }
}

/// Hardware-driven conic border ring that rotates at a strictly constant angular velocity in the
/// RenderServer, immune to SwiftUI transaction easing and preserving its angle across pause/resume.
private struct InspireSparkRing: UIViewRepresentable {
    let isSpinning: Bool

    func makeUIView(context: Context) -> InspireSparkRingView {
        let view = InspireSparkRingView()
        view.setSpinning(isSpinning)
        return view
    }

    func updateUIView(_ uiView: InspireSparkRingView, context: Context) {
        uiView.setSpinning(isSpinning)
    }
}

private final class InspireSparkRingView: UIView {
    private static let lap: CFTimeInterval = 7.0
    private static let lineWidth: CGFloat = 2.0
    private static let animationKey = "inspire.spark.spin"

    private static let cgColors: [CGColor] = {
        let alphas: [CGFloat] = [0.05, 0.05, 0.16, 0.38, 0.60, 0.32, 0.12, 0.05, 0.05]
        return alphas.map { alpha in
            UIColor(red: 0.968, green: 0.451, blue: 0.037, alpha: alpha).cgColor
        }
    }()

    private static let locations: [NSNumber] = [
        0.00, 0.20, 0.38, 0.50, 0.60, 0.70, 0.82, 0.92, 1.00,
    ]

    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()
    private var wantsSpin = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        gradientLayer.colors = Self.cgColors
        gradientLayer.locations = Self.locations
        layer.addSublayer(gradientLayer)

        maskLayer.fillColor = UIColor.clear.cgColor
        maskLayer.strokeColor = UIColor.white.cgColor
        maskLayer.lineWidth = Self.lineWidth
        layer.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.bounds = bounds
        gradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        maskLayer.frame = bounds
        let inset = Self.lineWidth / 2
        maskLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            applySpinState()
        }
    }

    func setSpinning(_ spinning: Bool) {
        guard wantsSpin != spinning || gradientLayer.animation(forKey: Self.animationKey) == nil else {
            return
        }
        wantsSpin = spinning
        applySpinState()
    }

    private func applySpinState() {
        if gradientLayer.animation(forKey: Self.animationKey) == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0.0
            spin.toValue = Double.pi * 2
            spin.duration = Self.lap
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            gradientLayer.add(spin, forKey: Self.animationKey)
        }

        if wantsSpin {
            if gradientLayer.speed == 0 {
                let pausedTime = gradientLayer.timeOffset
                gradientLayer.speed = 1.0
                gradientLayer.timeOffset = 0.0
                gradientLayer.beginTime = 0.0
                let elapsed = gradientLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
                gradientLayer.beginTime = elapsed
            }
        } else {
            if gradientLayer.speed != 0 {
                let pausedTime = gradientLayer.convertTime(CACurrentMediaTime(), from: nil)
                gradientLayer.speed = 0.0
                gradientLayer.timeOffset = pausedTime
            }
        }
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
