import SwiftUI

/// Close, the credit line, and during the onboarding taste the restore line and Renew.
struct ComposeHeader: View {
    let session: ComposeSession
    let edges: ComposeEdges
    var isOnboardingTaste: Bool
    var storeKitManager: StoreKitManager?
    var onClose: () -> Void
    var onShowMembership: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        Group {
            if showsTwoLineRestore {
                restoreHeader
            } else {
                HStack(alignment: .center, spacing: 12) {
                    leadingControl

                    Spacer(minLength: 0)

                    ComposeUsageLine(session: session)
                }
                .frame(minHeight: 40)
            }
        }
        .padding(.horizontal, ComposeLayout.edgePad)
        .padding(.top, 6)
        .padding(.bottom, showsTwoLineRestore ? 12 : 10)
        .animation(restoreAnimation, value: storeKitManager?.errorMessage)
        .animation(restoreAnimation, value: storeKitManager?.priorMembershipProductID)
        .task(id: showsOnboardingRestore) {
            guard showsOnboardingRestore else {
                return
            }
            await storeKitManager?.probeSubscriptionOffer()
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { edges.header = $0 }
    }

    /// Only the taste reads the session here, so a cook never redraws the regular header.
    private var showsOnboardingRestore: Bool {
        isOnboardingTaste && session.phase == .composing && session.statement.isEmpty
    }

    private var showsTwoLineRestore: Bool {
        showsOnboardingRestore
            && (storeKitManager?.hasEndedMembership == true || hasRestoreError)
    }

    private var hasRestoreError: Bool {
        guard let errorMessage = storeKitManager?.errorMessage, !errorMessage.isEmpty else {
            return false
        }
        return storeKitManager?.hasEndedMembership != true
    }

    private var restoreAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)
    }

    private var restoreSwapTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 10).combined(with: .opacity),
            removal: .offset(y: -8).combined(with: .opacity)
        )
    }

    private var restoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Text(restoreHeadlineText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .lineSpacing(4)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ComposeUsageLine(session: session)
            }
            .frame(minHeight: 40)

            if storeKitManager?.hasEndedMembership == true {
                renewButton
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var restoreHeadlineText: String {
        if storeKitManager?.hasEndedMembership == true {
            return storeKitManager?.errorMessage ?? "We found your previous subscription."
        }
        return storeKitManager?.errorMessage ?? ""
    }

    private var renewButton: some View {
        Button {
            guard storeKitManager?.isBusy != true else {
                return
            }
            onShowMembership()
        } label: {
            Text("Renew membership")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .link))
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager?.isBusy == true)
        .accessibilityLabel("View membership options")
        .transition(restoreSwapTransition)
    }

    @ViewBuilder
    private var leadingControl: some View {
        if !isOnboardingTaste {
            Button(action: onClose) {
                CircleIcon(
                    systemName: "xmark",
                    fill: theme.surface,
                    symbol: theme.ink,
                    weight: .semibold,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close without saving")
        } else {
            Color.clear
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}

/// "540 credits remaining". It reads the shared balance itself, so a cook redraws only this line.
private struct ComposeUsageLine: View {
    let session: ComposeSession

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ColorTokens.theme(colorScheme)
        if let status = session.usageStatus {
            let critical = session.usageIsCritical
            Text(status)
                .font(.caption.weight(critical ? .semibold : .medium))
                .foregroundStyle(critical ? theme.ink : theme.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(status)
        }
    }
}
