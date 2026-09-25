import SwiftUI

struct PaywallSpecimen: Identifiable, Equatable {
    let id: String
    let thought: String
    let reframe: String
    let style: Style

    init(id: String, thought: String, reframe: String, style: Style) {
        self.id = id
        self.thought = thought
        self.reframe = reframe
        self.style = style
    }

    init?(card: HomeCard) {
        let slide = card.slides.first(where: { $0.result.style == card.spotlightStyle }) ?? card.slides.first
        guard let slide else {
            return nil
        }
        let thought = card.thought.trimmingCharacters(in: .whitespacesAndNewlines)
        let reframe = slide.result.reframe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !thought.isEmpty, !reframe.isEmpty else {
            return nil
        }
        self.init(
            id: "saved-\(card.id.uuidString)",
            thought: thought,
            reframe: reframe,
            style: slide.result.style
        )
    }

    /// Shortened community-fixture cooks so a compact tile can hold them.
    static let catalog: [PaywallSpecimen] = [
        PaywallSpecimen(
            id: "freeze",
            thought: "I keep replaying how I froze when they asked me to walk through my impact.",
            reframe: "Name freezing in that meeting as a fact, not a trial. Put the verdict down and tend to the next small thing.",
            style: .stoic
        ),
        PaywallSpecimen(
            id: "deck",
            thought: "They presented my deck as theirs, and I sat there smiling like it was fine.",
            reframe: "Nothing about watching them take the deck cancels the person who noticed it. That noticing is already a kind of strength.",
            style: .optimistic
        ),
        PaywallSpecimen(
            id: "roundtable",
            thought: "My manager skipped me in the roundtable again and nobody even noticed.",
            reframe: "Congratulations, your brain made a documentary about being skipped that nobody asked to stream. Credits can roll.",
            style: .humorous
        ),
        PaywallSpecimen(
            id: "late-night",
            thought: "I said yes to another late night and I can feel myself disappearing.",
            reframe: "If saying yes again is true, act like it. If it is a story, stop feeding it snacks at midnight. The next move is yours.",
            style: .toughLove
        ),
        PaywallSpecimen(
            id: "passed-over",
            thought: "They hired someone above me and called it a chance for me to learn.",
            reframe: "Facts fit in a sentence; spirals do not. Shrink being passed over to its true size and let the rest of the day stay its own.",
            style: .stoic
        ),
        PaywallSpecimen(
            id: "fluent",
            thought: "Everyone else seems fluent in the room and I am translating myself.",
            reframe: "Your inner narrator needs an editor with a red pen and a bedtime. Fire the intern. Severance package: one nap.",
            style: .humorous
        ),
        PaywallSpecimen(
            id: "portal",
            thought: "I keep refreshing the hiring portal like staring will make them kinder.",
            reframe: "The sting is a hard chapter, not the whole book. You still get a next page that is not this refresh.",
            style: .optimistic
        ),
        PaywallSpecimen(
            id: "recap",
            thought: "I sent the recap and now I am hunting for the sentence that ruined me.",
            reframe: "You already know what the hunt costs. Quit romanticizing the loop and pick one adult action today.",
            style: .toughLove
        ),
        PaywallSpecimen(
            id: "slack",
            thought: "I keep drafting the slack and deleting it because I sound needy.",
            reframe: "Stay with it long enough to tell the truth, then stop decorating it. One true sentence is plenty.",
            style: .stoic
        )
    ]
}

struct PaywallCardMarquee: View {
    var savedCard: HomeCard? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        GeometryReader { geo in
            let itemWidth = max(220, geo.size.width * 0.62)
            ZStack {
                if reduceMotion {
                    marqueeStack(
                        bandWidth: geo.size.width,
                        bandHeight: geo.size.height,
                        itemWidth: itemWidth,
                        time: 0,
                        animate: false
                    )
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        marqueeStack(
                            bandWidth: geo.size.width,
                            bandHeight: geo.size.height,
                            itemWidth: itemWidth,
                            time: context.date.timeIntervalSinceReferenceDate,
                            animate: true
                        )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                edgeFades(bandHeight: geo.size.height)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func marqueeStack(
        bandWidth: CGFloat,
        bandHeight: CGFloat,
        itemWidth: CGFloat,
        time: TimeInterval,
        animate: Bool
    ) -> some View {
        VStack(spacing: PaywallMarqueeMetrics.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                PaywallMarqueeRow(
                    items: row,
                    itemWidth: itemWidth,
                    spacing: PaywallMarqueeMetrics.spacing,
                    speed: PaywallMarqueeMetrics.speeds[index % PaywallMarqueeMetrics.speeds.count],
                    reverse: index % 2 != 0,
                    time: time,
                    animate: animate
                )
                .frame(width: bandWidth, height: PaywallMarqueeMetrics.tileHeight, alignment: .leading)
            }
        }
        .frame(width: bandWidth, height: bandHeight, alignment: .top)
        .offset(y: -PaywallMarqueeMetrics.tileHeight * 0.12)
        .rotationEffect(.degrees(PaywallMarqueeMetrics.tilt))
        .scaleEffect(PaywallMarqueeMetrics.scale)
    }

    private var rows: [[PaywallSpecimen]] {
        let catalog = PaywallSpecimen.catalog
        var fade = [catalog[4], catalog[6], catalog[8]]
        let mainA = [catalog[0], catalog[1]]
        let mainB = [catalog[2], catalog[3]]
        let behind = [catalog[5], catalog[7]]
        if let savedCard, let extra = PaywallSpecimen(card: savedCard) {
            fade.insert(extra, at: 0)
        }
        return [fade, mainA, mainB, behind]
    }

    private func edgeFades(bandHeight: CGFloat) -> some View {
        let topFadeHeight = max(120, bandHeight * 0.22)
        /// Cover the purchase sheet, then run the same wash as the top in the strip above it.
        let sheetCover: CGFloat = 340
        let bottomFadeHeight = min(bandHeight * 0.72, topFadeHeight + sheetCover)
        let visibleEnd = max(0.18, min(0.5, topFadeHeight / bottomFadeHeight))

        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: theme.paper.opacity(0.88), location: 0),
                    .init(color: theme.paper.opacity(0.42), location: 0.55),
                    .init(color: theme.paper.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topFadeHeight)
            .frame(maxHeight: .infinity, alignment: .top)

            LinearGradient(
                stops: [
                    .init(color: theme.paper.opacity(0), location: 0),
                    .init(color: theme.paper.opacity(0.42), location: visibleEnd * 0.55),
                    .init(color: theme.paper.opacity(0.88), location: visibleEnd),
                    .init(color: theme.paper, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bottomFadeHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [theme.paper, theme.paper.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 28)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [theme.paper.opacity(0), theme.paper],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 28)
            }
        }
        .allowsHitTesting(false)
    }
}

private enum PaywallMarqueeMetrics {
    static let spacing: CGFloat = 12
    static let tileHeight: CGFloat = 192
    static let tilt: Double = -4
    static let scale: CGFloat = 1.12
    static let speeds: [CGFloat] = [22, 28, 24, 26]
}

private struct PaywallMarqueeRow: View {
    let items: [PaywallSpecimen]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let speed: CGFloat
    let reverse: Bool
    let time: TimeInterval
    let animate: Bool

    private var cycleWidth: CGFloat {
        guard !items.isEmpty else {
            return 0
        }
        return CGFloat(items.count) * (itemWidth + spacing)
    }

    var body: some View {
        HStack(spacing: spacing) {
            copy
            copy
        }
        .offset(x: horizontalOffset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var horizontalOffset: CGFloat {
        guard animate, cycleWidth > 1 else {
            return reverse ? -24 : 0
        }
        let travel = CGFloat(time) * speed
        let phase = travel.truncatingRemainder(dividingBy: cycleWidth)
        return reverse ? phase - cycleWidth : -phase
    }

    private var copy: some View {
        HStack(spacing: spacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, specimen in
                PaywallSpecimenTile(specimen: specimen, width: itemWidth)
            }
        }
    }
}

private struct PaywallSpecimenTile: View {
    let specimen: PaywallSpecimen
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var appearance: CardStyleAppearance { CardStyleAppearance(style: specimen.style) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(specimen.thought)
                .font(.footnote)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 15)
                .padding(.bottom, 10)

            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 1)
                .padding(.horizontal, 15)

            Text(specimen.reframe)
                .font(.callout.weight(.semibold))
                .foregroundStyle(appearance.responseInk)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 15)
                .padding(.top, 10)

            selectedChip
                .padding(.horizontal, 15)
                .padding(.bottom, 15)
        }
        .frame(width: width, height: PaywallMarqueeMetrics.tileHeight, alignment: .top)
        .background {
            appearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
    }

    private var selectedChip: some View {
        HStack(spacing: 6) {
            Image(systemName: appearance.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))

            Text(specimen.style.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(appearance.ink)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background {
            Capsule(style: .continuous)
                .fill(appearance.ink.opacity(appearance.chipFillOpacity(for: colorScheme)))
        }
    }
}
