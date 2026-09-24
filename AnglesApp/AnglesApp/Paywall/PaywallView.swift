import Lottie
import StoreKit
import SwiftUI

private enum PaywallPlan: String, CaseIterable, Identifiable {
    case annual
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annual:
            return "Yearly"
        case .monthly:
            return "Monthly"
        }
    }

    var productID: String {
        switch self {
        case .annual:
            return "app.angles.ios.annual"
        case .monthly:
            return "app.angles.ios.monthly"
        }
    }

    init?(productID: String) {
        switch productID {
        case StoreKitManager.annualProductID:
            self = .annual
        case StoreKitManager.monthlyProductID:
            self = .monthly
        default:
            return nil
        }
    }
}

private enum PaywallRevealStage {
    case celebrating
    case membership
}

struct PaywallView: View {
    let storeKitManager: StoreKitManager
    var showsCelebration = false
    var savedCard: HomeCard? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var selectedPlan: PaywallPlan = .annual
    @State private var hasChosenPlan = false
    @State private var stage: PaywallRevealStage
    @State private var completionHandled: Bool
    @State private var showsInfoSheet = false
    @State private var infoSheetDetent: PresentationDetent = .large

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var usesScrollableMembershipContent: Bool {
        verticalSizeClass == .compact || dynamicTypeSize > .large
    }

    init(
        storeKitManager: StoreKitManager,
        showsCelebration: Bool = false,
        savedCard: HomeCard? = nil
    ) {
        self.storeKitManager = storeKitManager
        self.showsCelebration = showsCelebration
        self.savedCard = savedCard
        let initialPlan = storeKitManager.priorMembershipProductID
            .flatMap { PaywallPlan(productID: $0) } ?? .annual
        _selectedPlan = State(initialValue: initialPlan)
        _stage = State(initialValue: showsCelebration ? .celebrating : .membership)
        _completionHandled = State(initialValue: !showsCelebration)
    }

    var body: some View {
        ZStack {
            AnglesCanvasBackground()
                .overlay {
                    if !theme.isDark {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(red: 0xE8 / 255, green: 0xE4 / 255, blue: 0xDC / 255).opacity(0.40)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                }

            if showsCelebratingHero {
                celebrationStage
                    .transition(.opacity)
            } else {
                membershipStage
                    .transition(membershipTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(theme.ink)
        .task {
            await runCelebrationWatchdog()
        }
        .task {
            await storeKitManager.probeSubscriptionOffer()
        }
        .task {
            if storeKitManager.products.isEmpty {
                await storeKitManager.loadProducts()
            }
        }
        .onChange(of: storeKitManager.priorMembershipProductID) { _, productID in
            guard !hasChosenPlan, let productID, let priorPlan = PaywallPlan(productID: productID) else {
                return
            }
            selectedPlan = priorPlan
        }
        .accessibilityElement(children: .contain)
    }

    private var showsCelebratingHero: Bool {
        showsCelebration && stage == .celebrating
    }

    /// Act 2 arrives as one group: a quiet rise under the celebration fade. No stagger.
    private var membershipTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }

    private var priorPlan: PaywallPlan? {
        guard let productID = storeKitManager.priorMembershipProductID else {
            return nil
        }
        return PaywallPlan(productID: productID)
    }

    private var celebrationStage: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            ZStack {
                if !reduceMotion {
                    PaywallHeroWash(diameter: 280)
                }

                Group {
                    if reduceMotion {
                        finalCheckmark
                    } else {
                        playingCheckmark
                    }
                }
                .frame(width: 220, height: 220)
            }

            Text("Saved privately")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.ink)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saved privately")
    }

    /// One locked screen: four-angle specimen on paper, commerce spread in the floor.
    /// The specimen scrolls only for compact height or larger Dynamic Type.
    private var membershipStage: some View {
        Group {
            if usesScrollableMembershipContent {
                ScrollView {
                    membershipContent(fillsAvailableHeight: false)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                membershipContent(fillsAvailableHeight: true)
            }
        }
        .animation(restoreFeedbackAnimation, value: storeKitManager.priorMembershipProductID)
        .animation(restoreFeedbackAnimation, value: storeKitManager.errorMessage)
        .animation(planSwitchAnimation, value: selectedPlan)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseModule
        }
        .sheet(isPresented: $showsInfoSheet) {
            paywallInfoSheet
                .onAppear { infoSheetDetent = .large }
        }
        .allowsHitTesting(!storeKitManager.isBusy || showsInfoSheet)
        .accessibilityHidden(storeKitManager.isBusy && !showsInfoSheet)
    }

    private func membershipContent(
        fillsAvailableHeight: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                infoButton
            }
            .padding(.horizontal, 8)

            VStack(spacing: 16) {
                Spacer(minLength: 8)

                Text("One thought. Four ways out.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                PaywallAngleGrid()

                Text("Without this, the next thought has nowhere to go.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 560)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsAvailableHeight ? .infinity : nil
            )
        }
    }

    private var infoButton: some View {
        Button {
            showsInfoSheet = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What’s included")
    }

    private var paywallInfoSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What’s included")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .tracking(-0.5)
                            .foregroundStyle(theme.ink)

                        Text("Membership keeps the practice going after the taste.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        infoIncludedRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Keep cooking",
                            detail: "The next thought gets four angles too. This wasn’t a one-time trick."
                        )
                        infoIncludedRow(
                            icon: "house.fill",
                            title: "Home",
                            detail: "See how others turned it around. You’re not the only one."
                        )
                    }

                    restoreButton

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Membership")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.sub)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        legalFooter
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(AnglesCanvasBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showsInfoSheet = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $infoSheetDetent)
        .presentationDragIndicator(.visible)
    }

    private func infoIncludedRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 40, height: 40)
                .background(theme.ink.opacity(theme.isDark ? 0.10 : 0.06), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.isDark ? theme.cardHairline : Color.black.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var priceType: some View {
        VStack(spacing: 6) {
            Text(heroPrice)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(heroPriceCaption)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heroPrice), \(heroPriceCaption)")
    }

    /// The floor of the screen: one elevated sheet holding the price, both plans, and the
    /// single action. Surface over paper is what separates commerce from content — the
    /// dark-mode fix.
    private var purchaseModule: some View {
        VStack(spacing: 22) {
            if let errorMessage = storeKitManager.errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(errorMessage)
            }

            priceType

            planRows

            purchaseButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            moduleBackground
        }
        .animation(planSwitchAnimation, value: selectedPlan)
        .animation(restoreFeedbackAnimation, value: storeKitManager.priorMembershipProductID)
    }

    private var moduleBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
            .fill(theme.surface)
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .strokeBorder(moduleEdge, lineWidth: 1)
            }
            .shadow(color: moduleShadow, radius: theme.isDark ? 18 : 20, y: theme.isDark ? -6 : -7)
            .ignoresSafeArea(edges: .bottom)
    }

    /// Light needs a real sheet edge; dark already has surface-on-paper contrast.
    private var moduleEdge: Color {
        theme.isDark ? theme.cardHairline : Color.black.opacity(0.06)
    }

    private var moduleShadow: Color {
        theme.isDark ? theme.shadowLift : Color.black.opacity(0.08)
    }

    /// Both plans, always visible. Yearly leads and is pre-selected; monthly stands as an
    /// equal row — nothing is hidden behind a text link.
    private var planRows: some View {
        VStack(spacing: 12) {
            planRow(.annual)
            planRow(.monthly)
        }
    }

    private func planRow(_ plan: PaywallPlan) -> some View {
        let isSelected = selectedPlan == plan
        let rowShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button {
            selectPlan(plan)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    planCopy(plan)

                    Spacer(minLength: 12)

                    planPriceAndSelection(plan, isSelected: isSelected)
                }

                VStack(alignment: .leading, spacing: 10) {
                    planCopy(plan)

                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        planPriceAndSelection(plan, isSelected: isSelected)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .background {
                rowShape.fill(theme.ink.opacity(isSelected ? 0.05 : 0))
            }
            .overlay {
                rowShape.strokeBorder(
                    isSelected ? theme.ink : (theme.isDark ? theme.cardHairline : Color.black.opacity(0.06)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager.isBusy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(planPrice(plan))")
        .accessibilityValue(planDetail(plan))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "" : "Double-tap to select")
    }

    private func planCopy(_ plan: PaywallPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(plan.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)

            Text(planDetail(plan))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func planPriceAndSelection(
        _ plan: PaywallPlan,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(planPrice(plan))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
                .contentTransition(.numericText())

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? theme.ink : theme.faint)
        }
    }

    private func planPrice(_ plan: PaywallPlan) -> String {
        let product = plan == .annual ? storeKitManager.annualProduct : storeKitManager.monthlyProduct
        if let product {
            return product.displayPrice
        }
        return "—"
    }

    private func planDetail(_ plan: PaywallPlan) -> String {
        switch plan {
        case .annual:
            if let monthly = monthlyEquivalentAmount(for: storeKitManager.annualProduct) {
                return "\(monthly) a month · billed yearly"
            }
            return "Billed yearly"
        case .monthly:
            return "Billed monthly"
        }
    }

    private var purchaseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await handlePrimaryAction()
            }
        } label: {
            HStack(spacing: 10) {
                if showsPrimarySpinner {
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
        .buttonStyle(PaywallPressStyle())
        .disabled(storeKitManager.isBusy)
        .opacity(storeKitManager.isBusy && !storeKitManager.isPurchasing ? 0.5 : 1)
        .accessibilityLabel(primaryButtonAccessibilityLabel)
    }

    private var restoreFeedbackAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)
    }

    private var planSwitchAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82)
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
                        .tint(theme.ink)
                }
                Text(storeKitManager.isRestoring ? "Restoring…" : "Restore purchases")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.isDark ? theme.cardHairline : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(storeKitManager.isBusy)
        .accessibilityLabel(storeKitManager.isRestoring ? "Restoring purchases" : "Restore purchases")
    }

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless canceled at least 24 hours before the current period ends.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.faint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    legalLinks
                }

                VStack(alignment: .leading, spacing: 10) {
                    legalLinks
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.ink)
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        Link(
            "Terms of Service",
            destination: URL(string: "https://angles.app/terms")!
        )
        Link(
            "Privacy Policy",
            destination: URL(string: "https://angles.app/privacy")!
        )
    }

    private var selectedProduct: Product? {
        storeKitManager.product(for: selectedPlan.productID)
    }

    private var showsPrimarySpinner: Bool {
        return storeKitManager.isPurchasing || (storeKitManager.isLoadingProducts && selectedProduct == nil)
    }

    private var primaryButtonTitle: String {
        if storeKitManager.isPurchasing {
            if let priorPlan {
                return selectedPlan == priorPlan ? "Renewing" : "Switching"
            }
            return "Subscribing"
        }
        if storeKitManager.isLoadingProducts && selectedProduct == nil {
            return "Loading"
        }
        if selectedProduct == nil {
            return "Retry"
        }
        if let priorPlan {
            return selectedPlan == priorPlan ? "Renew membership" : "Switch to \(selectedPlan.title)"
        }
        return "Continue"
    }

    private var primaryButtonAccessibilityLabel: String {
        if primaryButtonTitle == "Continue" {
            return "Continue, \(heroPrice), \(heroPriceCaption)"
        }
        if priorPlan != nil {
            return "\(primaryButtonTitle), \(heroPrice), \(heroPriceCaption)"
        }
        return primaryButtonTitle
    }

    private var heroPrice: String {
        switch selectedPlan {
        case .annual:
            if let monthly = monthlyEquivalentAmount(for: storeKitManager.annualProduct) {
                return monthly
            }
        case .monthly:
            if let price = storeKitManager.monthlyProduct?.displayPrice {
                return price
            }
        }
        if storeKitManager.isLoadingProducts {
            return "—"
        }
        return "Unavailable"
    }

    private var heroPriceCaption: String {
        switch selectedPlan {
        case .annual:
            if let price = storeKitManager.annualProduct?.displayPrice {
                return "a month, billed yearly at \(price)"
            }
            return "a month, billed yearly"
        case .monthly:
            return "a month, billed monthly"
        }
    }

    private func selectPlan(_ plan: PaywallPlan) {
        guard !storeKitManager.isBusy, selectedPlan != plan else {
            return
        }
        hasChosenPlan = true
        UISelectionFeedbackGenerator().selectionChanged()
        storeKitManager.clearError()
        withAnimation(planSwitchAnimation) {
            selectedPlan = plan
        }
    }

    private func handlePrimaryAction() async {
        if storeKitManager.isLoadingProducts {
            return
        }
        if selectedProduct == nil {
            await storeKitManager.loadProducts()
            return
        }
        await storeKitManager.purchase(productID: selectedPlan.productID)
    }

    private func monthlyEquivalentAmount(for product: Product?) -> String? {
        guard let product else {
            return nil
        }
        let monthly = product.price / 12
        return monthly.formatted(product.priceFormatStyle)
    }

    private var playingCheckmark: some View {
        LottieView(animation: .named("celebration-checkmark"))
            .playing()
            .animationDidFinish { finished in
                guard finished else {
                    return
                }
                Task { @MainActor in
                    await holdThenFinishCelebration()
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
        guard showsCelebration else {
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            await holdThenFinishCelebration(milliseconds: 700)
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(2500))
        } catch {
            return
        }
        finishCelebration()
    }

    @MainActor
    private func holdThenFinishCelebration(milliseconds: Int = 1100) async {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
        } catch {
            return
        }
        finishCelebration()
    }

    @MainActor
    private func finishCelebration() {
        guard showsCelebration, !completionHandled else {
            return
        }
        completionHandled = true

        if reduceMotion {
            stage = .membership
            return
        }

        withAnimation(.spring(response: 0.68, dampingFraction: 0.84)) {
            stage = .membership
        }
    }
}

private struct PaywallAngleGrid: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Style.allCases, id: \.self) { style in
                PaywallAngleTile(style: style)
            }
        }
    }
}

private struct PaywallAngleTile: View {
    let style: Style

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var appearance: CardStyleAppearance { CardStyleAppearance(style: style) }
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: appearance.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(appearance.ink)

                Text(style.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
            }

            Text(benefit)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(theme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background {
            tileFill
        }
        .clipShape(tileShape)
        .overlay {
            tileShape.strokeBorder(tileEdge, lineWidth: 1)
        }
        .shadow(color: tileShadow, radius: theme.isDark ? 10 : 12, y: theme.isDark ? 0 : 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.displayName). \(benefit)")
    }

    /// Midway: light tiles read as color without shouting. Dark is unchanged.
    private var tileFill: some View {
        let stops: (top: Double, mid: Double, bottom: Double) = theme.isDark
            ? (0.025, 0.06, 0.12)
            : (0.05, 0.11, 0.20)
        return theme.surface.overlay(
            LinearGradient(
                stops: [
                    .init(color: appearance.ink.opacity(stops.top), location: 0),
                    .init(color: appearance.ink.opacity(stops.mid), location: 0.55),
                    .init(color: appearance.ink.opacity(stops.bottom), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var tileEdge: Color {
        theme.isDark ? theme.cardHairline : appearance.ink.opacity(0.08)
    }

    private var tileShadow: Color {
        theme.isDark ? theme.cardAmbientShadow : Color.black.opacity(0.05)
    }

    private var benefit: String {
        switch style {
        case .stoic:
            return "What’s yours to carry, and what isn’t"
        case .optimistic:
            return "What could still go right"
        case .humorous:
            return "It doesn’t have to be this heavy"
        case .toughLove:
            return "Stop spinning. Next step."
        }
    }
}

private struct PaywallHeroCard: View {
    let card: HomeCard

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var spotlightSlide: HomeCardSlide? {
        card.slides.first(where: { $0.result.style == card.spotlightStyle }) ?? card.slides.first
    }

    private var appearance: CardStyleAppearance {
        CardStyleAppearance(style: spotlightSlide?.result.style ?? card.spotlightStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.thought)
                .font(ReframeCardMetrics.thoughtFont)
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle()
                .fill(theme.cardHairline)
                .frame(height: 1)
                .padding(.horizontal, 16)

            if let answer = spotlightSlide?.result.reframe {
                Text(answer)
                    .font(ReframeCardMetrics.answerFont)
                    .foregroundStyle(appearance.responseInk)
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            staticChips
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background {
            appearance.washFill(over: theme.surface)
        }
        .clipShape(cardShape)
        .modifier(ReframeCardElevationModifier(theme: theme, shape: cardShape))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var staticChips: some View {
        HStack(spacing: 8) {
            ForEach(card.slides.map(\.result.style), id: \.self) { style in
                staticChip(style)
            }
            Spacer(minLength: 0)
        }
    }

    private func staticChip(_ style: Style) -> some View {
        let chipAppearance = CardStyleAppearance(style: style)
        let isSelected = style == appearance.style

        return HStack(spacing: 6) {
            Image(systemName: chipAppearance.systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))

            if isSelected {
                Text(style.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(
            isSelected
                ? chipAppearance.ink
                : chipAppearance.ink.opacity(chipAppearance.chipUnselectedInkOpacity(for: colorScheme))
        )
        .padding(.horizontal, isSelected ? 10 : 0)
        .frame(width: isSelected ? nil : 30, height: 30, alignment: .center)
        .background {
            Capsule(style: .continuous)
                .fill(
                    chipAppearance.ink.opacity(
                        isSelected
                            ? chipAppearance.chipFillOpacity(for: colorScheme)
                            : chipAppearance.chipUnselectedFillOpacity(for: colorScheme)
                    )
                )
        }
        .accessibilityHidden(true)
    }

    private var accessibilityCopy: String {
        let thought = card.thought
        let answer = spotlightSlide?.result.reframe ?? ""
        let style = appearance.style.displayName
        return "\(thought). \(style): \(answer)"
    }
}

private struct PaywallHeroWash: View {
    let diameter: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
            ZStack {
                ForEach(Array(Style.allCases.enumerated()), id: \.offset) { index, style in
                    Circle()
                        .fill(CardStyleAppearance(style: style).ink.opacity(0.08 * Self.weight(index: index, t: t)))
                }
            }
            .frame(width: diameter, height: diameter)
            .blur(radius: 28)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func weight(index: Int, t: Double) -> Double {
        let center = (Double(index) + 0.5) / 4.0
        let delta = abs(t - center)
        let dist = min(delta, 1 - delta)
        return max(0, 1 - dist / 0.35)
    }
}

private struct PaywallPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview {
    PaywallView(storeKitManager: StoreKitManager())
}

struct CheckoutLockOverlay: View {
    let lines: [String]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineIndex = 0

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    private var currentLine: String {
        guard !lines.isEmpty else {
            return ""
        }
        return lines[min(lineIndex, lines.count - 1)]
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.ink)

                Text(currentLine)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .task(id: lines.joined(separator: "\n")) {
            lineIndex = 0
            guard !reduceMotion, lines.count > 1 else {
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2500))
                guard !Task.isCancelled, lines.count > 1 else {
                    return
                }
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    lineIndex = (lineIndex + 1) % lines.count
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(currentLine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
