import SwiftUI

enum StackMetrics {
    /// 16 points a side: the card is about 92% of the screen width.
    static let horizontalInset: CGFloat = 16
    /// How much of the card behind shows under the top card.
    static let sliver: CGFloat = 10
    static let behindScale: CGFloat = 0.94
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
    static let topGap: CGFloat = 22
    static let barGap: CGFloat = 14
    /// Height cap, as a multiple of the 6.1-inch card width. A wider phone wraps the same
    /// answer in fewer lines, so it does not get a taller card.
    static let maxAspect: CGFloat = 1.48
    static let referenceScreenWidth: CGFloat = 393

    /// How far the card and the action row rise together when the phone has spare height.
    static let lift: CGFloat = 16

    struct Frame: Equatable {
        var card: CGSize
        /// Header to card.
        var topGap: CGFloat
        /// The card behind's sliver to the action row.
        var barGap: CGFloat
        /// Spare taken from under the header and placed under the action row.
        var lift: CGFloat
    }

    static func frame(screen: CGSize, safeTop: CGFloat, safeBottom: CGFloat) -> Frame {
        let width = max(0, screen.width - StackMetrics.horizontalInset * 2)
        let header = safeTop + StackMetrics.headerHeight
        let bar = StackMetrics.inspireSize(screenHeight: screen.height) + StackMetrics.barBottom(safeBottom: safeBottom)
        let room = max(0, screen.height - header - bar - topGap - barGap - StackMetrics.sliver)
        let referenceWidth = referenceScreenWidth - StackMetrics.horizontalInset * 2
        let height = min(room, min(width, referenceWidth) * maxAspect)
        let spare = room - height
        let lift = min(Self.lift, spare / 2)
        return Frame(
            card: CGSize(width: width, height: height),
            topGap: topGap + spare / 2 - lift,
            barGap: barGap + spare / 2,
            lift: lift
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
    /// Up or down only: in from 40 to 70 points, out by 110, and gone once the finger goes sideways.
    /// Stored and updated only when it changes so horizontal swipes never redraw the hint capsule.
    var hintOpacity: Double = 0
    /// Only at accessibility sizes, where the card scrolls: set once a drag is known to be
    /// sideways, so a vertical scroll stays a scroll.
    @ObservationIgnored var isDeciding: Bool?
    /// Previous sample's raw translation so each frame adds only its own delta without a startup jump.
    @ObservationIgnored var lastTranslation: CGSize?
    /// Whether the finger has already crossed the release threshold this drag.
    @ObservationIgnored var pastThreshold = false

    /// -1 is a full lean toward Pass, 1 toward Love.
    var lean: CGFloat {
        max(-1, min(1, offset.width / StackMetrics.decideDistance))
    }

    /// The card behind grows into place as the top card is dragged away.
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

    func setOffset(_ next: CGSize) {
        offset = next
        let nextHint = Self.computeHintOpacity(for: next)
        if abs(nextHint - hintOpacity) > 0.005
            || (nextHint == 0 && hintOpacity != 0)
            || (nextHint == 1 && hintOpacity != 1)
        {
            hintOpacity = nextHint
        }
    }

    private static func computeHintOpacity(for offset: CGSize) -> Double {
        let vertical = abs(offset.height)
        let sideways = abs(offset.width)
        let rise = (vertical - 40) / 30
        let fall = (110 - vertical) / 40
        let straight = 1 - (sideways - 10) / 20
        return Double(max(0, min(1, rise, fall, straight)))
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
    @State private var decisionTick = 0
    @State private var thresholdTick = 0
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
                activeStyle: deck.top.map { deck.style(for: $0) },
                onFilter: { showFilter = true },
                onNotifications: openNotifications,
                onSettings: { showSettings = true }
            )
            .padding(.top, safeAreaInsets.top + HeaderCollapse.headerTopPad)

            cardArea
                .padding(.horizontal, StackMetrics.horizontalInset)
                .overlay(alignment: .bottom) { toast }
                .overlay(alignment: .top) {
                    StackDragHint(drag: drag)
                        .offset(y: -StackDragHint.height / 2)
                }
                .padding(.top, layout.topGap)
                .zIndex(1)

            StackActionBar(
                screenSize: screenSize,
                canRewind: deck.canRewind && flinging == nil,
                canDecide: deck.top != nil && flinging == nil,
                drag: drag,
                profilePulseToken: viewModel.profilePulseToken,
                onRewind: rewind,
                onPass: { fling(.pass) },
                onInspire: onInspire,
                onLove: { fling(.save) },
                onProfile: onOpenProfile
            )
            .padding(.top, layout.barGap)
            .padding(.bottom, StackMetrics.barBottom(safeBottom: safeAreaInsets.bottom) + layout.lift)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .background(theme.grey.ignoresSafeArea())
        .wideBackSwipe()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: decisionTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: thresholdTick)
        .onChange(of: stack.visitToken) { _, _ in
            resetDrag()
        }
        .sheet(isPresented: $showFilter) {
            StackFilterSheet(appliedFilter: stack.filter) { next in
                stack.apply(next)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            let size = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - StackMetrics.sliver))
            ZStack(alignment: .top) {
                if let top = deck.top {
                    if let behind = deck.behind {
                        StackBehindMotion(drag: drag) {
                            AngleCardFace(
                                card: behind,
                                sizing: .stack,
                                style: .constant(deck.style(for: behind)),
                                isInteractive: false,
                                isElevated: false,
                                actions: actions(for: behind)
                            )
                            .equatable()
                            .frame(width: size.width, height: size.height)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .id(behind.id)
                    }
                    topCard(top, size: size)
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

    private func topCard(_ card: HomeCard, size: CGSize) -> some View {
        StackTopMotion(drag: drag) {
            AngleCardFace(
                card: card,
                sizing: .stack,
                style: Binding(
                    get: { stack.deck.style(for: card) },
                    set: { stack.show($0, on: card.id) }
                ),
                isInteractive: flinging == nil,
                deviceTilt: deviceTilt,
                actions: actions(for: card)
            )
            .equatable()
            .frame(width: size.width, height: size.height)
        }
        .simultaneousGesture(dragGesture, including: flinging == nil ? .all : .none)
        .accessibilityAction(named: "Love") { fling(.save) }
        .accessibilityAction(named: "Pass") { fling(.pass) }
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
        .padding(.bottom, StackMetrics.sliver + 14)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.82), value: viewModel.postToast)
    }

    // MARK: - Decisions

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1.5, coordinateSpace: .global)
            .onChanged { value in
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
                    drag.setOffset(next)
                }
                let past = abs(next.width) >= StackMetrics.decideDistance
                if past, !drag.pastThreshold {
                    thresholdTick &+= 1
                }
                drag.pastThreshold = past
            }
            .onEnded { value in
                defer {
                    drag.isDeciding = nil
                    drag.lastTranslation = nil
                    drag.pastThreshold = false
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
                        drag.setOffset(.zero)
                    }
                }
            }
    }

    /// The card leaves first, then the decision commits, so the next card is never drawn mid-flight.
    private func fling(_ kind: DecisionKind) {
        guard flinging == nil, deck.top != nil else {
            return
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
            drag.hintOpacity = 0
        } completion: {
            commit(kind)
        }
    }

    private func commit(_ kind: DecisionKind) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stack.decide(kind)
            drag.setOffset(.zero)
            flinging = nil
        }
        decisionTick &+= 1
    }

    /// The last card comes back in from the side it left by.
    private func rewind() {
        guard flinging == nil else {
            return
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        var entrance: CGSize = .zero
        withTransaction(transaction) {
            guard let step = stack.rewind() else {
                return
            }
            let direction: CGFloat = step.kind == .save ? 1 : -1
            entrance = CGSize(width: direction * max(drag.cardWidth, 320) * 1.3, height: 30)
            drag.setOffset(reduceMotion ? .zero : entrance)
        }
        decisionTick &+= 1
        guard !reduceMotion, entrance != .zero else {
            return
        }
        Task { @MainActor [drag] in
            await Task.yield()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                drag.setOffset(.zero)
            }
        }
    }

    private func resetDrag() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drag.setOffset(.zero)
            drag.isDeciding = nil
            drag.lastTranslation = nil
            drag.pastThreshold = false
            flinging = nil
        }
    }
}

// MARK: - Motion

/// The top card's tilt, offset, and stamps: the only part of Home that redraws per drag frame.
private struct StackTopMotion<Content: View>: View {
    let drag: StackDrag
    let content: Content

    init(drag: StackDrag, @ViewBuilder content: () -> Content) {
        self.drag = drag
        self.content = content()
    }

    var body: some View {
        content
            .overlay { StackStamps(lean: drag.lean) }
            .rotationEffect(drag.tilt, anchor: .bottom)
            .offset(drag.offset)
    }
}

/// The card behind: a step smaller, a sliver lower, and in shadow until the top card moves away.
private struct StackBehindMotion<Content: View>: View {
    let drag: StackDrag
    let content: Content

    init(drag: StackDrag, @ViewBuilder content: () -> Content) {
        self.drag = drag
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let progress = drag.progress
        let shade = (colorScheme == .dark ? 0.35 : 0.10) * Double(1 - progress)
        content
            .overlay {
                RoundedRectangle(cornerRadius: AngleCardMetrics.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(shade))
                    .allowsHitTesting(false)
            }
            .scaleEffect(StackMetrics.behindScale + (1 - StackMetrics.behindScale) * progress, anchor: .bottom)
            .offset(y: StackMetrics.sliver * (1 - progress))
    }
}

// MARK: - Header

/// Filter on the left, the six style dots in the middle, notifications and Settings on the right.
private struct StackHeader: View {
    let filterCount: Int
    let hasUnread: Bool
    let activeStyle: Style?
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

            StyleDotsMark(active: activeStyle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activeStyle.map { "Angles, \($0.displayName)" } ?? "Angles")
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

/// A whisper while the finger moves up or down: only the sides decide.
private struct StackDragHint: View {
    static let height: CGFloat = 24

    let drag: StackDrag

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        let opacity = drag.hintOpacity
        Text("Swipe sideways to love or pass")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.sub)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.cardHairline, lineWidth: 0.5))
            .opacity(opacity)
            .animation(.easeOut(duration: 0.15), value: opacity == 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
