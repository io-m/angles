import Lottie
import SwiftUI

private enum SuccessRevealStage {
    case celebrating
    case benefits
}

struct PaywallGlimpseView: View {
    var safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    var onContinue: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @Namespace private var checkmarkNamespace
    @State private var stage: SuccessRevealStage = .celebrating
    @State private var completionHandled = false
    @State private var headerCopyIsVisible = false
    @State private var visibleBenefitCount = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private let successGreen = Color(red: 0.20, green: 0.74, blue: 0.35)
    private let successDeep = Color(red: 0.08, green: 0.47, blue: 0.25)
    private let successMint = Color(red: 0.64, green: 0.92, blue: 0.72)

    var body: some View {
        ZStack {
            frostedBackdrop

            switch stage {
            case .celebrating:
                celebrationStage
                    .transition(.opacity)
            case .benefits:
                benefitsStage
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            await runCelebrationWatchdog()
        }
        .accessibilityElement(children: .contain)
    }

    private var celebrationStage: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            playingCheckmark
                .frame(width: 220, height: 220)
                .matchedGeometryEffect(
                    id: "success-checkmark",
                    in: checkmarkNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: true
                )

            Text("Saved privately")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)

            Spacer(minLength: 0)
        }
        .padding(.top, safeAreaInsets.top)
        .padding(.bottom, safeAreaInsets.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saved privately")
    }

    private var benefitsStage: some View {
        ScrollView {
            VStack(spacing: 0) {
                successHeader
                    .padding(.bottom, 26)

                VStack(spacing: 12) {
                    benefitTile(
                        index: 0,
                        symbol: "square.stack.3d.up.fill",
                        color: successGreen,
                        title: "Shift the thought",
                        detail: "Four distinct angles help loosen a loop and reveal a way through."
                    )
                    benefitTile(
                        index: 1,
                        symbol: "person.2.fill",
                        color: Color(red: 0.15, green: 0.65, blue: 0.61),
                        title: "You’re not alone",
                        detail: "Explore anonymous thoughts others chose to share and find what resonates."
                    )
                    benefitTile(
                        index: 2,
                        symbol: "lock.shield.fill",
                        color: Color(red: 0.23, green: 0.56, blue: 0.78),
                        title: "Keep your inner world yours",
                        detail: "Private by default. No profiling. No data selling."
                    )
                }

                Spacer(minLength: 24)

                continueButton
            }
            .padding(.horizontal, 20)
            .padding(.top, max(22, safeAreaInsets.top + 12))
            .padding(.bottom, max(20, safeAreaInsets.bottom + 12))
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var frostedBackdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            theme.surface
                .opacity(colorScheme == .dark ? 0.62 : 0.50)

            RadialGradient(
                colors: [
                    successMint.opacity(colorScheme == .dark ? 0.10 : 0.08),
                    .clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                EllipticalGradient(
                    stops: [
                        .init(color: successGreen.opacity(colorScheme == .dark ? 0.22 : 0.16), location: 0),
                        .init(color: successMint.opacity(colorScheme == .dark ? 0.12 : 0.09), location: 0.42),
                        .init(color: successMint.opacity(0.03), location: 0.72),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.68),
                    startRadiusFraction: 0.04,
                    endRadiusFraction: 1
                )
                .frame(height: 340)
                .offset(y: 88)
                .blur(radius: 24)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var successHeader: some View {
        VStack(spacing: 14) {
            finalCheckmark
                .frame(width: 92, height: 92)
                .matchedGeometryEffect(
                    id: "success-checkmark",
                    in: checkmarkNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: false
                )
                .shadow(color: successGreen.opacity(0.22), radius: 18)

            VStack(spacing: 12) {
                Text("SAVED PRIVATELY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(successDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(successMint.opacity(colorScheme == .dark ? 0.12 : 0.24), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(successGreen.opacity(0.20), lineWidth: 1)
                    }

                VStack(spacing: 8) {
                    Text("A little lighter already.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-0.7)
                        .foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)

                    Text("Your thought is safe. Here’s what opens up next.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.muted)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(headerCopyIsVisible ? 1 : 0)
            .offset(y: reduceMotion || headerCopyIsVisible ? 0 : 10)
        }
        .animation(
            reduceMotion ? .linear(duration: 0.16) : .spring(response: 0.44, dampingFraction: 0.86),
            value: headerCopyIsVisible
        )
        .accessibilityElement(children: .combine)
    }

    private func benefitTile(
        index: Int,
        symbol: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(colorScheme == .dark ? 0.17 : 0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.ink)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.surface.opacity(0.91))
                .overlay {
                    LinearGradient(
                        colors: [color.opacity(colorScheme == .dark ? 0.12 : 0.075), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(color.opacity(colorScheme == .dark ? 0.22 : 0.16), lineWidth: 1)
        }
        .shadow(color: color.opacity(colorScheme == .dark ? 0.06 : 0.08), radius: 16, y: 5)
        .opacity(visibleBenefitCount > index ? 1 : 0)
        .offset(y: reduceMotion || visibleBenefitCount > index ? 0 : 16)
        .scaleEffect(reduceMotion || visibleBenefitCount > index ? 1 : 0.96)
        .animation(
            reduceMotion ? .linear(duration: 0.16) : .spring(response: 0.48, dampingFraction: 0.83),
            value: visibleBenefitCount
        )
        .accessibilityElement(children: .combine)
    }

    private var continueButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: 10) {
                Text("Continue to plans")
                    .font(.system(size: 16, weight: .semibold))

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [successGreen, successDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .shadow(color: successGreen.opacity(0.22), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .opacity(visibleBenefitCount == 3 ? 1 : 0)
        .offset(y: reduceMotion || visibleBenefitCount == 3 ? 0 : 10)
        .animation(
            reduceMotion ? .linear(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.86),
            value: visibleBenefitCount
        )
        .accessibilityHint("Opens subscription plans")
    }

    private var playingCheckmark: some View {
        LottieView(animation: .named("celebration-checkmark"))
            .playing()
            .animationDidFinish { finished in
                guard finished else {
                    return
                }
                Task { @MainActor in
                    finishCelebration()
                }
            }
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var finalCheckmark: some View {
        LottieView(animation: .named("celebration-checkmark"))
            .paused(at: .progress(1))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    @MainActor
    private func runCelebrationWatchdog() async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            finishCelebration()
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(900))
        } catch {
            return
        }
        finishCelebration()
    }

    @MainActor
    private func finishCelebration() {
        guard !completionHandled else {
            return
        }
        completionHandled = true

        if reduceMotion {
            stage = .benefits
            headerCopyIsVisible = true
            visibleBenefitCount = 3
            return
        }

        withAnimation(.spring(response: 0.68, dampingFraction: 0.84)) {
            stage = .benefits
        }

        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            headerCopyIsVisible = true

            for count in 1...3 {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
                visibleBenefitCount = count
            }
        }
    }
}

#Preview {
    ZStack {
        AnglesCanvasBackground()
        PaywallGlimpseView(onContinue: {})
    }
}
