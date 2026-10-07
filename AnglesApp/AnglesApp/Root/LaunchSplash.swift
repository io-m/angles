import SwiftUI

enum LaunchSplashPhase: Equatable {
    case holding
    case exiting
    case finished
}

enum LaunchSplashMotion {
    /// Minimum time so the smooth float-in is appreciated before exiting.
    static let minimumHold: Duration = .milliseconds(850)
    static let markSize: CGFloat = 96

    /// Entrance choreography.
    static let entranceDuration: TimeInterval = 0.50
    static let initialScale: CGFloat = 0.92
    static let initialGlow: Double = 0.15
    static let restingGlow: Double = 0.35

    /// Aperture punch exit choreography.
    static let anticipationDuration: TimeInterval = 0.16
    static let anticipationScale: CGFloat = 0.88
    static let punchDuration: TimeInterval = 0.44
    static let exitScale: CGFloat = 36.0
    static let reduceMotionExitDuration: TimeInterval = 0.28
}

/// Cold-launch cover. Always dark, independent of the user's appearance.
/// Executes a smooth float-in entrance, then an aperture punch zoom-through into Home.
struct LaunchSplash: View {
    var isExiting: Bool
    var reduceMotion: Bool
    var onFinished: () -> Void

    @State private var markScale: CGFloat = LaunchSplashMotion.initialScale
    @State private var markOpacity: Double = 0.0
    @State private var glowOpacity: Double = LaunchSplashMotion.initialGlow
    @State private var backgroundOpacity: Double = 1.0
    @State private var overlayOpacity: Double = 1.0
    @State private var didPlayExit = false

    var body: some View {
        ZStack {
            splashBackground
                .opacity(backgroundOpacity)

            InspireMark(size: LaunchSplashMotion.markSize)
                .scaleEffect(markScale)
                .opacity(markOpacity)
        }
        .opacity(overlayOpacity)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Angles")
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

    private var splashBackground: some View {
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
                    InspireMark.brandColor.opacity(glowOpacity),
                    InspireMark.brandColor.opacity(glowOpacity * 0.3),
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
    }

    private func playExitIfNeeded() {
        guard !didPlayExit else {
            return
        }
        didPlayExit = true

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

        // Phase 1: Anticipation dip (scale down to 0.88 over 160ms)
        withAnimation(.easeInOut(duration: LaunchSplashMotion.anticipationDuration)) {
            markScale = LaunchSplashMotion.anticipationScale
            glowOpacity = 0.45
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(LaunchSplashMotion.anticipationDuration * 1000)))
            guard !Task.isCancelled else { return }

            // Phase 2: Explosive punch (scale up to 36x over 440ms with steep bezier)
            withAnimation(.timingCurve(0.7, 0, 0.15, 1, duration: LaunchSplashMotion.punchDuration)) {
                markScale = LaunchSplashMotion.exitScale
            }

            // Phase 3: Dissolve timing
            // Mark dissolves as wings fly offscreen
            withAnimation(.easeOut(duration: 0.22).delay(0.16)) {
                markOpacity = 0
            }

            // Background dissolves over 0.25s during peak expansion, revealing Home
            withAnimation(.easeInOut(duration: 0.25).delay(0.14)) {
                backgroundOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(Int(LaunchSplashMotion.punchDuration * 1000)))
            onFinished()
        }
    }
}
