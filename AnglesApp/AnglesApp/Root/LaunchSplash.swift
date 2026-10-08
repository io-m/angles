import SwiftUI

enum LaunchSplashPhase: Equatable {
    case holding
    case exiting
    case finished
}

enum LaunchSplashMotion {
    /// Floor so the float-in is seen. Punch still fires as soon as Home is ready after this.
    static let minimumHold: Duration = .milliseconds(850)
    /// Above a 2–4s local fetch so punch waits on the request, not this cap.
    static let maximumHold: Duration = .milliseconds(6000)
    static let markSize: CGFloat = 96

    static let entranceDuration: TimeInterval = 0.50
    static let initialScale: CGFloat = 0.92
    static let initialGlow: Double = 0.15
    static let restingGlow: Double = 0.35

    /// Clock-driven one-way rise. A 2–4s fetch lands partway; punch takes over from there.
    static let waitDuration: TimeInterval = 6.0
    static let waitScale: CGFloat = 2.0
    static let waitGlow: Double = 0.5

    static let shimmerHighlight = Color(red: 0.74, green: 0.66, blue: 0.58)
    static let shimmerShade = Color(red: 0.48, green: 0.40, blue: 0.34)
    static let ripplePeriod: TimeInterval = 2.4

    static let punchDuration: TimeInterval = 0.44
    static let exitScale: CGFloat = 36.0
    static let reduceMotionExitDuration: TimeInterval = 0.28
}

/// Cold-launch cover. Always dark, independent of the user's appearance.
/// Floats in, slowly scales and ripples while /feed runs, then punches when it returns.
struct LaunchSplash: View {
    var isExiting: Bool
    var reduceMotion: Bool
    var onFinished: () -> Void

    @State private var markScale: CGFloat = LaunchSplashMotion.initialScale
    @State private var markOpacity: Double = 0.0
    @State private var glowOpacity: Double = LaunchSplashMotion.initialGlow
    @State private var rippleOpacity: Double = 0
    @State private var backgroundOpacity: Double = 1.0
    @State private var overlayOpacity: Double = 1.0
    @State private var didPlayExit = false
    @State private var isWaiting = false
    @State private var waitStartedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isWaiting || didPlayExit)) { context in
            ZStack {
                splashBackground(glow: displayedGlow(at: context.date))
                    .opacity(backgroundOpacity)

                mark
                    .scaleEffect(displayedScale(at: context.date))
                    .opacity(markOpacity)
            }
        }
        .opacity(overlayOpacity)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Angles")
        .accessibilityHint(isWaiting ? "Loading" : "")
        .onChange(of: isExiting) { _, exiting in
            if exiting {
                playExitIfNeeded()
            }
        }
        .onAppear {
            if reduceMotion {
                markScale = 1.0
                markOpacity = 1.0
                glowOpacity = LaunchSplashMotion.restingGlow
            } else {
                playEntrance()
            }
            if isExiting {
                playExitIfNeeded()
            }
        }
    }

    private func displayedScale(at date: Date) -> CGFloat {
        if didPlayExit {
            return markScale
        }
        guard isWaiting, let start = waitStartedAt else {
            return markScale
        }
        let t = waitProgress(at: date, started: start)
        return 1.0 + (LaunchSplashMotion.waitScale - 1.0) * t
    }

    private func displayedGlow(at date: Date) -> Double {
        if didPlayExit {
            return glowOpacity
        }
        guard isWaiting, let start = waitStartedAt else {
            return glowOpacity
        }
        let t = waitProgress(at: date, started: start)
        return LaunchSplashMotion.restingGlow
            + (LaunchSplashMotion.waitGlow - LaunchSplashMotion.restingGlow) * Double(t)
    }

    private func waitProgress(at date: Date, started: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(started)
        return CGFloat(min(1, max(0, elapsed / LaunchSplashMotion.waitDuration)))
    }

    private var mark: some View {
        let size = LaunchSplashMotion.markSize
        return InspireMark(size: size)
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isWaiting)) { context in
                    ripples(at: context.date, size: size)
                }
                .mask(InspireMark(size: size))
                .opacity(rippleOpacity)
            }
    }

    private func ripples(at date: Date, size: CGFloat) -> some View {
        let elapsed = waitStartedAt.map { date.timeIntervalSince($0) } ?? 0
        let period = LaunchSplashMotion.ripplePeriod
        return ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                let shifted = elapsed / period + Double(index) / 3
                let phase = CGFloat(shifted.truncatingRemainder(dividingBy: 1))
                Circle()
                    .strokeBorder(
                        LaunchSplashMotion.shimmerHighlight.opacity(rippleAlpha(phase)),
                        lineWidth: 2.2 - phase * 1.1
                    )
                    .scaleEffect(0.18 + phase * 1.15)
                    .blur(radius: 0.6 + phase * 1.4)
            }
        }
        .frame(width: size, height: size)
        .blendMode(.overlay)
        .overlay {
            RadialGradient(
                colors: [
                    LaunchSplashMotion.shimmerHighlight.opacity(0.10),
                    LaunchSplashMotion.shimmerShade.opacity(0.04),
                    Color.clear,
                ],
                center: .center,
                startRadius: 4,
                endRadius: size * 0.55
            )
            .blendMode(.overlay)
        }
    }

    private func rippleAlpha(_ phase: CGFloat) -> Double {
        let fadeIn = min(1, Double(phase) / 0.18)
        let fadeOut = max(0, 1 - Double(phase))
        return 0.34 * fadeIn * fadeOut
    }

    private func splashBackground(glow: Double) -> some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(
                        color: Color(red: 0.12, green: 0.09, blue: 0.07),
                        location: 0
                    ),
                    .init(color: ColorTokens.paperDark, location: 0.46),
                    .init(
                        color: Color(red: 0.06, green: 0.055, blue: 0.05),
                        location: 1
                    ),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    InspireMark.brandColor.opacity(glow),
                    InspireMark.brandColor.opacity(glow * 0.3),
                    Color.clear,
                ],
                center: .center,
                startRadius: 8,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }

    private func playEntrance() {
        withAnimation(.easeOut(duration: LaunchSplashMotion.entranceDuration)) {
            markScale = 1.0
            markOpacity = 1.0
            glowOpacity = LaunchSplashMotion.restingGlow
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(LaunchSplashMotion.entranceDuration))
            guard !Task.isCancelled, !didPlayExit, !reduceMotion else {
                return
            }
            startWaiting()
        }
    }

    private func startWaiting() {
        waitStartedAt = Date()
        isWaiting = true
        withAnimation(.easeOut(duration: 0.4)) {
            rippleOpacity = 1
        }
    }

    private func playExitIfNeeded() {
        guard !didPlayExit else {
            return
        }
        let currentScale = displayedScale(at: Date())
        let currentGlow = displayedGlow(at: Date())
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            markScale = currentScale
            glowOpacity = currentGlow
            didPlayExit = true
            isWaiting = false
        }

        if reduceMotion {
            withAnimation(.easeOut(duration: LaunchSplashMotion.reduceMotionExitDuration)) {
                overlayOpacity = 0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(LaunchSplashMotion.reduceMotionExitDuration))
                onFinished()
            }
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            rippleOpacity = 0
        }

        withAnimation(.timingCurve(0.7, 0, 0.15, 1, duration: LaunchSplashMotion.punchDuration)) {
            markScale = LaunchSplashMotion.exitScale
            glowOpacity = 0.2
        }

        withAnimation(.easeOut(duration: 0.22).delay(0.16)) {
            markOpacity = 0
        }

        withAnimation(.easeInOut(duration: 0.25).delay(0.14)) {
            backgroundOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(LaunchSplashMotion.punchDuration))
            onFinished()
        }
    }
}
