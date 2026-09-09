import SwiftUI

struct HomeView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 12
        static let drawerWidth: CGFloat = 88
        static let contentShift: CGFloat = 96
        static let fabSize: CGFloat = 56
        static let fabGap: CGFloat = 8
    }

    let onOpenDestination: (DrawerDestination) -> Void
    let safeAreaInsets: EdgeInsets

    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var menuProgress: CGFloat = 0
    @State private var isMenuActive = false
    @State private var isComposePresented = false

    @State private var dragTracker = DrawerDragTracker()

    init(
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenDestination: @escaping (DrawerDestination) -> Void = { _ in }
    ) {
        self.safeAreaInsets = safeAreaInsets
        self.onOpenDestination = onOpenDestination
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = safeAreaInsets.top
            let safeBottom = safeAreaInsets.bottom

            ZStack {
                AnglesCanvasBackground()

                mainChrome(
                    safeTop: safeTop,
                    safeBottom: safeBottom,
                    size: geometry.size
                )
                .offset(x: -Layout.contentShift * menuProgress)

                edgeFades(safeTop: safeTop, safeBottom: safeBottom)

                composerDock(safeBottom: safeBottom)
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .bottom
                    )
                    .offset(x: -Layout.contentShift * menuProgress)

                if isMenuActive {
                    closeOverlay(size: geometry.size)
                        .offset(x: -Layout.contentShift * menuProgress)
                        .drawerCloseGesture(closeDragGesture, isEnabled: true)
                }

                drawer(safeTop: safeTop, safeBottom: safeBottom)

                menuButton(safeBottom: safeBottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(.anglesAccent)
        .sheet(isPresented: $isComposePresented, onDismiss: viewModel.resetCompose) {
            ComposeSheetView(viewModel: viewModel)
        }
    }

    private func mainChrome(
        safeTop: CGFloat,
        safeBottom: CGFloat,
        size: CGSize
    ) -> some View {
        HomeCardGrid(
            cards: viewModel.cards,
            usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
            isScrollDisabled: isMenuActive,
            horizontalPadding: Layout.horizontalPadding,
            spacing: Layout.gridSpacing,
            topPadding: safeTop + 30,
            bottomPadding: safeBottom + 142
        )
        .equatable()
        .frame(width: size.width, height: size.height)
    }

    private func closeOverlay(size: CGSize) -> some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: closeMenu)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close menu")
    }

    private func edgeFades(safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: .anglesCanvasTop.opacity(0.86), location: 0),
                    Gradient.Stop(color: .anglesCanvasTop.opacity(0.58), location: 0.38),
                    Gradient.Stop(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeTop + 44)

            Spacer()

            LinearGradient(
                stops: [
                    Gradient.Stop(color: .clear, location: 0),
                    Gradient.Stop(color: .anglesCanvasBottom.opacity(0.58), location: 0.58),
                    Gradient.Stop(color: .anglesCanvasBottom.opacity(0.86), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeBottom + 164)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func composerDock(safeBottom: CGFloat) -> some View {
        HStack(spacing: Layout.fabGap) {
            Button {
                viewModel.resetCompose()
                isComposePresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.anglesAccent)

                    Text("Tell me what's on your mind...")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.anglesPlaceholder)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.anglesSurface, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 16, y: 7)
                .shadow(color: Color.anglesAccent.opacity(0.16), radius: 10, y: 4)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New reframe")

            Color.clear
                .frame(width: Layout.fabSize, height: Layout.fabSize)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.bottom, max(safeBottom, 10) + 12)
        .opacity(isComposePresented ? 0 : 1)
        .allowsHitTesting(!isComposePresented)
    }

    private func drawer(safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(spacing: 14) {
            ForEach(DrawerDestination.allCases) { destination in
                Button {
                    closeMenu()
                    onOpenDestination(destination)
                } label: {
                    Image(systemName: destination.systemImage)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.anglesAccent)
                        .frame(width: 52, height: 52)
                        .background(Color.anglesAccent.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.rawValue)
            }

            Spacer()
        }
        .padding(.top, safeTop + 24)
        .padding(.bottom, safeBottom + 80)
        .frame(width: Layout.drawerWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .opacity(menuProgress)
        .offset(x: (1 - menuProgress) * Layout.drawerWidth)
        .allowsHitTesting(isMenuActive)
        .accessibilityHidden(!isMenuActive)
    }

    private func menuButton(safeBottom: CGFloat) -> some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button(action: toggleMenu) {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(45 * menuProgress))
                        .frame(width: Layout.fabSize, height: Layout.fabSize)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.anglesAccentLight,
                                            Color.anglesAccent,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .contentShape(Circle())
                        .shadow(color: Color.anglesAccent.opacity(0.32), radius: 14, y: 6)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMenuActive ? "Close menu" : "Open menu")
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.bottom, max(safeBottom, 10) + 12)
        }
        .opacity(isComposePresented ? 0 : 1)
        .allowsHitTesting(!isComposePresented)
    }

    private var closeDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard isMenuActive, !dragTracker.rejectedVerticalDrag else {
            return
        }

        if dragTracker.lastSampleTime == nil {
            dragTracker.startProgress = menuProgress
            dragTracker.lastSampleTime = value.time
            dragTracker.lastTranslationX = value.translation.width
        }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if !dragTracker.isHorizontalDrag {
            if verticalDistance > 12, verticalDistance > horizontalDistance {
                dragTracker.rejectedVerticalDrag = true
                return
            }

            guard value.translation.width > 4, horizontalDistance > verticalDistance else {
                updateDragSample(value)
                return
            }

            dragTracker.isHorizontalDrag = true
        }

        updateDragSample(value)

        guard !reduceMotion else {
            return
        }

        let closeDistance = max(0, value.translation.width)
        let nextProgress = min(
            1,
            max(0, dragTracker.startProgress - (closeDistance / Layout.contentShift))
        )

        guard abs(nextProgress - menuProgress) >= 0.001 else {
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            menuProgress = nextProgress
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer { resetDragTracking() }

        guard isMenuActive,
              dragTracker.isHorizontalDrag,
              !dragTracker.rejectedVerticalDrag else {
            return
        }

        let releaseProgress: CGFloat
        if reduceMotion {
            releaseProgress = min(
                1,
                max(
                    0,
                    dragTracker.startProgress
                        - (max(0, value.translation.width) / Layout.contentShift)
                )
            )
        } else {
            releaseProgress = menuProgress
        }

        let projectedVelocity = max(
            0,
            (value.predictedEndTranslation.width - value.translation.width) / 0.25
        )
        let velocity = max(dragTracker.velocityX, projectedVelocity)
        let shouldClose = releaseProgress <= 0.70 || velocity >= 900
        let target: CGFloat = shouldClose ? 0 : 1
        let duration = settleDuration(
            from: releaseProgress,
            to: target,
            velocityX: velocity
        )

        settleMenu(to: target, duration: duration)
    }

    private func updateDragSample(_ value: DragGesture.Value) {
        if let previousTime = dragTracker.lastSampleTime {
            let elapsed = value.time.timeIntervalSince(previousTime)
            if elapsed > 0 {
                dragTracker.velocityX = (
                    value.translation.width - dragTracker.lastTranslationX
                ) / elapsed
            }
        }

        dragTracker.lastSampleTime = value.time
        dragTracker.lastTranslationX = value.translation.width
    }

    private func resetDragTracking() {
        dragTracker.reset()
    }

    private func toggleMenu() {
        if isMenuActive {
            closeMenu()
        } else {
            openMenu()
        }
    }

    private func openMenu() {
        guard !isComposePresented else {
            return
        }

        isMenuActive = true

        if reduceMotion {
            menuProgress = 1
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                menuProgress = 1
            }
        }
    }

    private func closeMenu() {
        settleMenu(to: 0, duration: 0.17)
    }

    private func settleMenu(to target: CGFloat, duration: TimeInterval) {
        if reduceMotion {
            menuProgress = target
            isMenuActive = target > 0
            return
        }

        withAnimation(.linear(duration: duration), completionCriteria: .logicallyComplete) {
            menuProgress = target
        } completion: {
            if target == 0 {
                isMenuActive = false
            }
        }
    }

    private func settleDuration(
        from progress: CGFloat,
        to target: CGFloat,
        velocityX: CGFloat
    ) -> TimeInterval {
        let remainingProgress = target == 0 ? progress : 1 - progress
        let remainingDistance = max(0, remainingProgress) * Layout.contentShift
        let velocityTowardTarget = target == 0
            ? max(0, velocityX)
            : max(0, -velocityX)
        let speed = max(600, velocityTowardTarget)
        let duration = TimeInterval(remainingDistance / speed)
        return min(0.220, max(0.048, duration))
    }
}

private struct RotatingHomeTitle: View {
    private static let phrases = [
        "A kinder angle",
        "A calmer take",
        "A clearer view",
        "A softer read",
        "A wiser turn",
        "A lighter hold",
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Text(Self.phrases[index])
                .font(.title.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .id(Self.phrases[index])
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .clipped()
        .accessibilityElement()
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Self.phrases[index])
        .task {
            await rotatePhrases()
        }
    }

    private func rotatePhrases() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3.5))
            } catch {
                return
            }

            let nextIndex = (index + 1) % Self.phrases.count
            if reduceMotion {
                index = nextIndex
            } else {
                withAnimation(.easeInOut(duration: 0.45)) {
                    index = nextIndex
                }
            }
        }
    }
}

private struct HomeCardGrid: View, Equatable {
    let cards: [HomeCard]
    let usesSingleColumn: Bool
    let isScrollDisabled: Bool
    let horizontalPadding: CGFloat
    let spacing: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    private var columns: [GridItem] {
        if usesSingleColumn {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                Section {
                    ForEach(cards) { card in
                        ReframeCardView(card: card)
                    }
                } header: {
                    RotatingHomeTitle()
                        .padding(.horizontal, 2)
                        .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(isScrollDisabled)
    }
}

private final class DrawerDragTracker {
    var startProgress: CGFloat = 1
    var isHorizontalDrag = false
    var rejectedVerticalDrag = false
    var lastSampleTime: Date?
    var lastTranslationX: CGFloat = 0
    var velocityX: CGFloat = 0

    func reset() {
        startProgress = 1
        isHorizontalDrag = false
        rejectedVerticalDrag = false
        lastSampleTime = nil
        lastTranslationX = 0
        velocityX = 0
    }
}

private extension View {
    @ViewBuilder
    func drawerCloseGesture<G: Gesture>(
        _ gesture: G,
        isEnabled: Bool
    ) -> some View {
        if isEnabled {
            highPriorityGesture(gesture)
        } else {
            self
        }
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView()
    }
}
