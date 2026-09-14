import SwiftUI

private enum PaywallPlan: String, CaseIterable, Identifiable {
    case annual
    case monthly

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .annual:
            return "app.angles.ios.annual"
        case .monthly:
            return "app.angles.ios.monthly"
        }
    }
}

struct PaywallView: View {
    let storeKitManager: StoreKitManager

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentPalette) private var accentPalette
    @State private var selectedPlan: PaywallPlan = .annual

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ZStack {
            theme.paper
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    logo
                        .padding(.top, 34)
                        .padding(.bottom, 24)

                    VStack(spacing: 10) {
                        Text("Unlock Angles.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .tracking(-0.8)
                            .foregroundStyle(theme.ink)
                            .multilineTextAlignment(.center)

                        Text("Unlimited perspectives for whenever your mind loops.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(theme.muted)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)

                    VStack(spacing: 12) {
                        planCard(.annual)
                        planCard(.monthly)
                    }
                    .padding(.horizontal, 20)

                    if let errorMessage = storeKitManager.errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 28)
                            .padding(.top, 14)
                            .accessibilityLabel(errorMessage)
                    }

                    purchaseButton
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    restoreButton
                        .padding(.top, 14)

                    legalFooter
                        .padding(.horizontal, 28)
                        .padding(.top, 22)
                        .padding(.bottom, 26)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .tint(theme.ink)
        .task {
            if storeKitManager.products.isEmpty {
                await storeKitManager.loadProducts()
            }
        }
    }

    private var logo: some View {
        ZStack {
            Circle()
                .fill(accentPalette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                .frame(width: 104, height: 104)
                .blur(radius: 24)

            Circle()
                .fill(theme.surface)
                .frame(width: 76, height: 76)
                .overlay {
                    Circle().strokeBorder(theme.cardHairline, lineWidth: 1)
                }
                .shadow(color: theme.shadowLift, radius: 16, y: 5)

            Image(systemName: "sparkle")
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Angles")
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let selected = selectedPlan == plan

        return Button {
            guard !storeKitManager.isBusy else {
                return
            }
            UISelectionFeedbackGenerator().selectionChanged()
            storeKitManager.clearError()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                radio(isSelected: selected)
                    .padding(.top, plan == .annual ? 4 : 2)

                VStack(alignment: .leading, spacing: 7) {
                    if plan == .annual {
                        Text("BEST VALUE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(theme.ink)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accentPalette.accent.opacity(0.22), in: Capsule())
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(plan == .annual ? "Annual" : "Monthly")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.ink)

                        Spacer(minLength: 8)

                        Text(priceLine(for: plan))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.ink)
                    }

                    if plan == .annual {
                        Text("$3.33/mo")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.muted)
                    }

                    Text(plan == .annual
                         ? "Billed annually at $39.99. Cancel anytime."
                         : "Billed monthly. Cancel anytime.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? theme.surface : theme.grey.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        selected ? theme.ink.opacity(0.72) : theme.cardHairline,
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .shadow(color: selected ? theme.shadowLift : .clear, radius: 14, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan == .annual ? "Annual plan" : "Monthly plan")
        .accessibilityValue(selected ? "Selected, \(priceLine(for: plan))" : priceLine(for: plan))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func radio(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(isSelected ? theme.ink : theme.faint, lineWidth: 1.5)
            .frame(width: 22, height: 22)
            .overlay {
                if isSelected {
                    Circle()
                        .fill(theme.ink)
                        .frame(width: 12, height: 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .accessibilityHidden(true)
    }

    private var purchaseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await storeKitManager.purchase(productID: selectedPlan.productID)
            }
        } label: {
            HStack(spacing: 10) {
                if storeKitManager.isPurchasing {
                    ProgressView()
                        .tint(theme.paper)
                }

                Text(primaryButtonTitle)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(theme.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(theme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: theme.shadowLift, radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager.isBusy)
        .opacity(storeKitManager.isBusy && !storeKitManager.isPurchasing ? 0.5 : 1)
        .accessibilityLabel(primaryButtonTitle)
    }

    private var restoreButton: some View {
        Button {
            Task {
                await storeKitManager.restorePurchases()
            }
        } label: {
            HStack(spacing: 8) {
                if storeKitManager.isRestoring {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(storeKitManager.isRestoring ? "Restoring Purchases" : "Restore Purchases")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(theme.ink)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager.isBusy)
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the current period ends.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(theme.faint)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://angles.app/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://angles.app/privacy")!)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.muted)
        }
    }

    private var primaryButtonTitle: String {
        if storeKitManager.isPurchasing {
            return "Subscribing"
        }
        return selectedPlan == .annual ? "Subscribe Annually" : "Subscribe Monthly"
    }

    private func priceLine(for plan: PaywallPlan) -> String {
        let fallback = plan == .annual ? "$39.99" : "$4.99"
        let displayPrice: String
        switch plan {
        case .annual:
            displayPrice = storeKitManager.annualProduct?.displayPrice ?? fallback
        case .monthly:
            displayPrice = storeKitManager.monthlyProduct?.displayPrice ?? fallback
        }
        return "\(displayPrice) / \(plan == .annual ? "year" : "month")"
    }
}

#Preview {
    PaywallView(storeKitManager: StoreKitManager())
}
