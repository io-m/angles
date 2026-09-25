import AuthenticationServices
import SwiftUI

struct LoginView: View {
    var sessionStore: SessionStore
    var onRetryRestore: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            AnglesCanvasBackground()
            LoginAtmosphere(expanded: reduceMotion ? false : breathing)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            LoginCardStage()
                .padding(.bottom, LoginChrome.dockClearance)
                .safeAreaPadding(.bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)

            VStack(spacing: 0) {
                hero
                    .padding(.top, 12)
                Spacer(minLength: 0)
                dock
            }
            .zIndex(2)
        }
        .opacity(sessionStore.isBusy ? 0.94 : 1)
        .onAppear(perform: beginBreathing)
        .onChange(of: reduceMotion) { _, _ in
            beginBreathing()
        }
    }

    private func beginBreathing() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            breathing = false
        }
        guard !reduceMotion else {
            return
        }
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 6.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Style.allCases, id: \.self) { style in
                    Circle()
                        .fill(CardStyleAppearance(style: style).ink)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("ANGLES")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(4.8)
                    .foregroundStyle(theme.muted)

                Text("Reframe your mind.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)

                Text("Four angles on the same situation.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.sub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Angles. Reframe your mind. Four angles on the same situation.")
    }

    private var dock: some View {
        VStack(spacing: 14) {
            SignInWithAppleButton(.continue) { request in
                sessionStore.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await sessionStore.completeApple(result) }
            }
            .signInWithAppleButtonStyle(theme.isDark ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(sessionStore.isBusy)
            .accessibilityLabel("Continue with Apple")

            if sessionStore.isBusy {
                ProgressView()
                    .controlSize(.regular)
                    .tint(theme.ink)
                    .accessibilityLabel("Signing in")
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("No password. Face ID is enough.")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(theme.muted)
                .accessibilityElement(children: .combine)
            }

            if let errorMessage = sessionStore.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.sub)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)

                if sessionStore.session == nil, AuthCredentials.shared.bearerToken != nil {
                    Button("Try again") {
                        onRetryRestore()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.ink)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .safeAreaPadding(.bottom)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                topTrailingRadius: 32,
                style: .continuous
            )
            .fill(theme.surface)
            .shadow(color: theme.cardAmbientShadow, radius: 24, x: 0, y: -8)
            .shadow(color: theme.cardAmbientCore, radius: 10, x: 0, y: -2)
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 32,
                    topTrailingRadius: 32,
                    style: .continuous
                )
                .strokeBorder(theme.cardHairline, lineWidth: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private enum LoginChrome {
    static let dockClearance: CGFloat = 148
}

private struct LoginAtmosphere: View {
    var expanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let span = min(geo.size.width, geo.size.height)
            ZStack {
                bloom(
                    style: .stoic,
                    size: span * 0.92,
                    x: geo.size.width * 0.08,
                    y: geo.size.height * 0.12,
                    inverted: false,
                    restOpacity: 0.20,
                    spanOpacity: 0.14
                )
                bloom(
                    style: .optimistic,
                    size: span * 0.86,
                    x: geo.size.width * 0.92,
                    y: geo.size.height * 0.16,
                    inverted: true,
                    restOpacity: 0.18,
                    spanOpacity: 0.12
                )
                bloom(
                    style: .humorous,
                    size: span * 0.78,
                    x: geo.size.width * 0.12,
                    y: geo.size.height * 0.78,
                    inverted: true,
                    restOpacity: 0.16,
                    spanOpacity: 0.12
                )
                bloom(
                    style: .toughLove,
                    size: span * 0.88,
                    x: geo.size.width * 0.90,
                    y: geo.size.height * 0.82,
                    inverted: false,
                    restOpacity: 0.18,
                    spanOpacity: 0.14
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bloom(
        style: Style,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        inverted: Bool,
        restOpacity: Double,
        spanOpacity: Double
    ) -> some View {
        let lit = inverted ? !expanded : expanded
        let ink = CardStyleAppearance(style: style).ink
        let isDark = colorScheme == .dark
        let pulse = restOpacity + spanOpacity * (lit ? 1 : 0)
        let layer = isDark ? pulse : pulse * 1.18
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        ink.opacity(isDark ? 0.55 : 0.50),
                        ink.opacity(isDark ? 0.08 : 0.12),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .opacity(layer)
            .position(x: x, y: y)
            .blur(radius: 28)
    }
}

private enum LoginSample {
    static let front = HomeCard(
        createdAt: Date().addingTimeInterval(-2 * 3600),
        slides: [
            slide(
                freezeThought,
                .stoic,
                "Name freezing in that meeting as a fact, not a trial. Put the verdict down and tend to the next small thing.",
                favorite: true
            ),
            slide(
                freezeThought,
                .optimistic,
                "The freeze was a moment, not a verdict on you. You still get to walk through the impact — next time, on your terms."
            ),
            slide(
                freezeThought,
                .humorous,
                "Your brain hit pause like it was buffering a 4K TED talk. Credits can roll. You can still send the recap."
            ),
            slide(
                freezeThought,
                .toughLove,
                "You froze. Fine. Replay is not rehearsal. Write the three bullets they asked for and stop auditioning the moment."
            ),
        ],
        spotlightStyle: .stoic,
        isPublic: false,
        isOwner: false,
        authorInitials: "A",
        model: .mistral,
        meta: workMeta(tags: ["meeting"], emotions: [.shame, .fear])
    )

    static let mid = HomeCard(
        createdAt: Date().addingTimeInterval(-5 * 3600),
        slides: [
            slide(
                deckThought,
                .optimistic,
                "Nothing about watching them take the deck cancels the person who noticed it. That noticing is already a kind of strength.",
                favorite: true
            ),
            slide(
                deckThought,
                .stoic,
                "They presented the work. Stay with what is yours to do next, not the replay of the smile you offered."
            ),
            slide(
                deckThought,
                .humorous,
                "You sat there smiling like a stock photo. The plot twist is you still made the slides."
            ),
            slide(
                deckThought,
                .toughLove,
                "If it was yours, say so once, clearly. If you won’t, stop renting the scene a room in your head."
            ),
        ],
        spotlightStyle: .optimistic,
        isPublic: false,
        isOwner: false,
        authorInitials: "R",
        model: .mistral,
        meta: workMeta(tags: ["credit"], emotions: [.anger, .shame])
    )

    static let back = HomeCard(
        createdAt: Date().addingTimeInterval(-26 * 3600),
        slides: [
            slide(
                lateThought,
                .toughLove,
                "If saying yes again is true, act like it. If it is a story, stop feeding it snacks at midnight. The next move is yours.",
                favorite: true
            ),
            slide(
                lateThought,
                .stoic,
                "Another late night is a choice with a cost. Name the cost, then pick the next hour on purpose."
            ),
            slide(
                lateThought,
                .optimistic,
                "Disappearing is a feeling, not a finished fact. You still get a morning that is not this shift."
            ),
            slide(
                lateThought,
                .humorous,
                "You RSVP’d to vanishing. Bold. Maybe decline the encore and go to bed like a person with bones."
            ),
        ],
        spotlightStyle: .toughLove,
        isPublic: false,
        isOwner: false,
        authorInitials: "M",
        model: .mistral,
        meta: workMeta(tags: ["hours"], emotions: [.overwhelm, .sadness])
    )

    private static let freezeThought =
        "I keep replaying how I froze when they asked me to walk through my impact."
    private static let deckThought =
        "They presented my deck as theirs, and I sat there smiling like it was fine."
    private static let lateThought =
        "I said yes to another late night and I can feel myself disappearing."

    private static func slide(
        _ thought: String,
        _ style: Style,
        _ reframe: String,
        favorite: Bool = false
    ) -> HomeCardSlide {
        HomeCardSlide(
            id: UUID(),
            thought: thought,
            result: ReframeResult(style: style, reframe: reframe),
            isFavorite: favorite
        )
    }

    private static func workMeta(tags: [String], emotions: [Emotion]) -> ReframeMeta {
        ReframeMeta(
            category: .work,
            tags: tags,
            intensity: 4,
            timeframe: .ongoing,
            emotions: emotions,
            safety: .none,
            inputLanguage: "en",
            skippedStyles: [],
            matching: MatchingKey(category: .work, tags: tags, intensityBand: .high)
        )
    }
}

private struct LoginCardRest {
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
    var fallRotation: Double
}

private struct LoginCardFloat {
    var period: Double
    var lift: CGFloat
    var tilt: Double
    var driftX: CGFloat
    var phaseDelay: Double
}

private struct LoginCardStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let fallDistance = geo.size.height + ReframeCardMetrics.storedMinimumHeight + 48
            let depth = geo.size.height > 520 ? 3 : 1

            ZStack(alignment: .bottom) {
                if depth > 2 {
                    LoginFallingCard(
                        card: LoginSample.back,
                        opening: .toughLove,
                        rest: LoginCardRest(
                            x: 22,
                            y: -46,
                            rotation: 7,
                            scale: 0.90,
                            opacity: 0.78,
                            fallRotation: 12
                        ),
                        float: LoginCardFloat(
                            period: 5.2,
                            lift: 8,
                            tilt: 1.8,
                            driftX: 4,
                            phaseDelay: 0
                        ),
                        fallDistance: fallDistance,
                        startDelay: 0.40
                    )
                }

                if depth > 1 {
                    LoginFallingCard(
                        card: LoginSample.mid,
                        opening: .optimistic,
                        rest: LoginCardRest(
                            x: -16,
                            y: -22,
                            rotation: -6,
                            scale: 0.95,
                            opacity: 0.90,
                            fallRotation: -11
                        ),
                        float: LoginCardFloat(
                            period: 6.4,
                            lift: 6,
                            tilt: -1.4,
                            driftX: -5,
                            phaseDelay: 0.40
                        ),
                        fallDistance: fallDistance,
                        startDelay: 0.62
                    )
                }

                LoginFallingCard(
                    card: LoginSample.front,
                    opening: .stoic,
                    rest: LoginCardRest(
                        x: 0,
                        y: 0,
                        rotation: 0,
                        scale: 1,
                        opacity: 1,
                        fallRotation: 8
                    ),
                    float: LoginCardFloat(
                        period: 7.6,
                        lift: 5,
                        tilt: 0.8,
                        driftX: 3,
                        phaseDelay: 0.80
                    ),
                    fallDistance: fallDistance,
                    startDelay: depth > 1 ? 0.84 : 0.40
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}

private struct LoginFallingCard: View {
    let card: HomeCard
    let opening: Style
    let rest: LoginCardRest
    let float: LoginCardFloat
    let fallDistance: CGFloat
    let startDelay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false
    @State private var floating = false

    var body: some View {
        ReframeCardView(
            card: card,
            presentation: .library,
            menuRole: .feed,
            openingStyle: opening
        )
        .scaleEffect(rest.scale)
        .rotationEffect(.degrees(rotation))
        .offset(x: offsetX, y: offsetY)
        .opacity(opacity)
        .onAppear(perform: play)
        .onChange(of: reduceMotion) { _, _ in
            play()
        }
    }

    private var rotation: Double {
        if !landed {
            return rest.rotation + rest.fallRotation
        }
        if floating {
            return rest.rotation + float.tilt
        }
        return rest.rotation
    }

    private var offsetX: CGFloat {
        if !landed {
            return rest.x
        }
        if floating {
            return rest.x + float.driftX
        }
        return rest.x
    }

    private var offsetY: CGFloat {
        if !landed {
            return rest.y - fallDistance
        }
        if floating {
            return rest.y + float.lift
        }
        return rest.y
    }

    private var opacity: Double {
        landed ? rest.opacity : 0
    }

    private func play() {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) {
            landed = reduceMotion
            floating = false
        }
        guard !reduceMotion else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(startDelay * 1000)))
            withAnimation(.spring(response: 0.78, dampingFraction: 0.70)) {
                landed = true
            }
            try? await Task.sleep(for: .milliseconds(900))
            try? await Task.sleep(for: .milliseconds(Int(float.phaseDelay * 1000)))
            withAnimation(.easeInOut(duration: float.period).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

#Preview {
    LoginView(sessionStore: SessionStore())
}
