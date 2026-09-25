import StoreKit
import SwiftUI

/// Settings → Subscription. Status and plan come from StoreKit; change and cancel
/// both open Apple's manage-subscriptions sheet. The app never cancels itself.
struct SubscriptionView: View {
    let storeKitManager: StoreKitManager

    @Environment(\.colorScheme) private var colorScheme

    @State private var isOpeningManage = false
    @State private var manageError: String?
    @State private var usage: UsageSummary?
    @State private var isLoadingUsage = false
    @State private var usageError: String?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var isSubscribed: Bool { storeKitManager.subscriptionStatus == .subscribed }
    private let profileService = ProfileService()

    /// Yearly wears the amber wash, monthly the slate-blue one. Same families as style cards.
    private var planInk: Color {
        switch storeKitManager.activeProductID {
        case StoreKitManager.annualProductID:
            return CardStyleAppearance(style: .optimistic).ink
        case StoreKitManager.monthlyProductID:
            return CardStyleAppearance(style: .stoic).ink
        default:
            return isSubscribed
                ? CardStyleAppearance(style: .humorous).ink
                : theme.muted
        }
    }

    var body: some View {
        ModalScreen(title: "Subscription") {
            VStack(alignment: .leading, spacing: 16) {
                statusCard

                usageCard

                if isSubscribed {
                    actionRow(
                        symbol: "arrow.left.arrow.right",
                        title: "Change plan",
                        subtitle: "Switch Yearly or Monthly in the App Store",
                        ink: CardStyleAppearance(style: .stoic).ink
                    ) {
                        Task { await openManageSubscriptions() }
                    }

                    actionRow(
                        symbol: "xmark",
                        title: "Cancel",
                        subtitle: "Manage renewal in the App Store",
                        ink: CardStyleAppearance(style: .toughLove).ink
                    ) {
                        Task { await openManageSubscriptions() }
                    }
                }

                actionRow(
                    symbol: "arrow.clockwise",
                    title: storeKitManager.isRestoring ? "Checking…" : "Restore purchases",
                    subtitle: "Find a subscription already on this Apple ID",
                    ink: CardStyleAppearance(style: .humorous).ink
                ) {
                    Task { await storeKitManager.restorePurchases() }
                }
                .disabled(storeKitManager.isRestoring || isOpeningManage)
                .opacity(storeKitManager.isRestoring || isOpeningManage ? 0.55 : 1)

                if isOpeningManage || storeKitManager.isRestoring {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(planInk)
                        Text(isOpeningManage ? "Opening App Store…" : "Checking with Apple…")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }

                if let message = manageError ?? storeKitManager.errorMessage, !message.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .accessibilityLabel(message)

                        if storeKitManager.serverSyncPending {
                            Button("Retry membership sync") {
                                Task { await storeKitManager.retryServerSync() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.ink)
                            .disabled(storeKitManager.isBusy)
                            .accessibilityHint("Retries syncing your Apple subscription with Angles")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
        }
        .task {
            await loadUsage()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text(isSubscribed ? "Active" : "Inactive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(planInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(planInk.opacity(colorScheme == .dark ? 0.22 : 0.14), in: Capsule())

                Spacer(minLength: 8)

                Image(systemName: isSubscribed ? "checkmark.seal.fill" : "creditcard")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(planInk)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isSubscribed ? (storeKitManager.activePlanTitle ?? "Subscribed") : "No plan")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.ink)

                if isSubscribed, let price = storeKitManager.activeProduct?.displayPrice {
                    Text("\(price) \(cadence)")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(planInk)
                } else if !isSubscribed {
                    Text("Nothing is billing on this Apple ID.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.muted)
                }
            }

            if isSubscribed {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(renewalLine)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(theme.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.surface)
                .overlay {
                    LinearGradient(
                        colors: [
                            planInk.opacity(colorScheme == .dark ? 0.34 : 0.22),
                            planInk.opacity(colorScheme == .dark ? 0.10 : 0.06),
                            Color.clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(planInk.opacity(colorScheme == .dark ? 0.45 : 0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var cadence: String {
        storeKitManager.activeProductID == StoreKitManager.annualProductID ? "per year" : "per month"
    }

    @ViewBuilder
    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Credits")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)

                Spacer(minLength: 8)

                if isLoadingUsage {
                    ProgressView()
                        .controlSize(.small)
                        .tint(planInk)
                        .accessibilityLabel("Loading credits")
                }
            }

            if let usage {
                Text("\(usage.creditsRemaining) of \(usage.creditsGranted) credits")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .contentTransition(.numericText())

                ProgressView(
                    value: Double(max(0, usage.creditsRemaining)),
                    total: Double(max(1, usage.creditsGranted))
                )
                .tint(planInk)
                .accessibilityLabel("Credits remaining")
                .accessibilityValue("\(usage.creditsRemaining) of \(usage.creditsGranted)")

                Text(usageResetLine(usage))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.muted)
            } else if let usageError {
                Text(usageError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Retry") {
                    Task { await loadUsage() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.ink)
                .disabled(isLoadingUsage)
                .accessibilityHint("Reloads your credit balance")
            } else {
                Text("Loading your credit balance…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.cardHairline, lineWidth: 1)
        }
    }

    private func usageResetLine(_ usage: UsageSummary) -> String {
        guard let resetDate = usage.resetDate else {
            return "Credits reset with your membership period"
        }
        return "Resets \(resetDate.formatted(date: .abbreviated, time: .omitted))"
    }

    @MainActor
    private func loadUsage() async {
        guard !isLoadingUsage else {
            return
        }
        isLoadingUsage = true
        usageError = nil
        defer { isLoadingUsage = false }
        do {
            usage = try await profileService.usage()
        } catch is CancellationError {
            return
        } catch {
            usageError = "Couldn't load your credits. Check your connection and try again."
        }
    }

    private var renewalLine: String {
        StoreKitManager.activeUntilLine(for: storeKitManager.activeExpiresAt)
    }

    private func actionRow(
        symbol: String,
        title: String,
        subtitle: String,
        ink: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(ink.opacity(colorScheme == .dark ? 0.22 : 0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @MainActor
    private func openManageSubscriptions() async {
        manageError = nil
        isOpeningManage = true
        defer { isOpeningManage = false }

        if let scene = UIApplication.shared.connectedScenes.first(where: {
            $0.activationState == .foregroundActive
        }) as? UIWindowScene ?? UIApplication.shared.connectedScenes.first as? UIWindowScene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                await storeKitManager.refreshEntitlements()
                return
            } catch {
                Self.debugLog("manage subscriptions sheet failed: \(error.localizedDescription)")
            }
        }

        guard let url = URL(string: "https://apps.apple.com/account/subscriptions"),
              await UIApplication.shared.open(url) else {
            manageError = "Couldn’t open Apple subscriptions. Manage it in the App Store app."
            return
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[Angles Subscription] \(message)")
        #endif
    }
}
