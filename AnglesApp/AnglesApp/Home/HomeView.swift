import SwiftUI

struct HomeView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let gridSpacing: CGFloat = 12
        static let headerHeight: CGFloat = 44
    }

    let safeAreaInsets: EdgeInsets

    @ObservedObject var viewModel: HomeViewModel
    @Binding var isComposePresented: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentPalette) private var accentPalette
    @EnvironmentObject private var themeStore: ThemeStore

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    @State private var showSettings = false

    @MainActor
    init(
        viewModel: HomeViewModel? = nil,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        isComposePresented: Binding<Bool> = .constant(false)
    ) {
        self.viewModel = viewModel ?? HomeViewModel()
        self.safeAreaInsets = safeAreaInsets
        self._isComposePresented = isComposePresented
    }

    var body: some View {
        homeChrome
            .ignoresSafeArea(.keyboard)
            .animation(nil, value: isComposePresented)
            .toolbar(.hidden, for: .navigationBar)
            .tint(accentPalette.accent)
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.grey)
                    .modifier(UserAppearance(store: themeStore))
            }
    }

    private var homeChrome: some View {
        GeometryReader { geometry in
            let safeTop = safeAreaInsets.top
            let safeBottom = safeAreaInsets.bottom

            ZStack {
                AnglesCanvasBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header

                        HomeCardGrid(
                            cards: viewModel.cards,
                            usesSingleColumn: dynamicTypeSize.isAccessibilitySize,
                            spacing: Layout.gridSpacing,
                            onEdit: editCard,
                            onDelete: deleteCard
                        )
                        .equatable()
                    }
                    .padding(.horizontal, Layout.horizontalPadding)
                    .padding(.top, safeTop + 6)
                    .padding(.bottom, safeBottom + 80)
                }
                .scrollIndicators(.hidden)
                .frame(width: geometry.size.width, height: geometry.size.height)

                topFade(safeTop: safeTop)
                bottomFade(safeBottom: safeBottom)
            }
            .overlay(alignment: .bottomTrailing) {
                composerDock(safeBottom: safeBottom)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RotatingHomeTitle()

            Button {
                showSettings = true
            } label: {
                CircleIcon(
                    systemName: "gearshape",
                    fill: theme.surface,
                    symbol: theme.ink,
                    hairline: theme.cardHairline
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(minHeight: Layout.headerHeight, alignment: .center)
    }

    private func topFade(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: theme.paper.opacity(0.97), location: 0),
                    Gradient.Stop(color: theme.paper.opacity(0.86), location: 0.55),
                    Gradient.Stop(color: theme.paper.opacity(0.42), location: 0.82),
                    Gradient.Stop(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeTop)

            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bottomFade(safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()

            LinearGradient(
                stops: [
                    Gradient.Stop(color: .clear, location: 0),
                    Gradient.Stop(color: theme.grey.opacity(0.58), location: 0.58),
                    Gradient.Stop(color: theme.grey.opacity(0.86), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeBottom + 56)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func composerDock(safeBottom: CGFloat) -> some View {
        Button {
            presentCompose()
        } label: {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(fabSymbol)
                .frame(width: 56, height: 56)
                .background(fabFill, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(fabSymbol.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
                .shadow(color: accentPalette.accent.opacity(0.18), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspire me")
        .padding(.trailing, Layout.horizontalPadding)
        .padding(.bottom, max(safeBottom, 10) + 12)
    }

    private var fabFill: Color {
        if colorScheme == .dark {
            return Color(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF8 / 255)
        }
        return Color(red: 0x0C / 255, green: 0x0B / 255, blue: 0x0A / 255)
    }

    private var fabSymbol: Color {
        if colorScheme == .dark {
            return Color(red: 0x14 / 255, green: 0x13 / 255, blue: 0x12 / 255)
        }
        return Color(red: 0xFD / 255, green: 0xFB / 255, blue: 0xF8 / 255)
    }

    private func presentCompose() {
        viewModel.resetCompose()
        isComposePresented = true
    }

    private func editCard(_ card: HomeCard) {
        viewModel.beginEdit(card)
        isComposePresented = true
    }

    private func deleteCard(_ card: HomeCard) {
        withAnimation(.easeInOut(duration: 0.22)) {
            viewModel.deleteCard(card.id)
        }
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var index = 0

    var body: some View {
        Text(Self.phrases[index])
            .font(.title.bold())
            .foregroundStyle(ColorTokens.theme(colorScheme).ink)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(Self.phrases[index])
            .transition(.opacity)
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
    let spacing: CGFloat
    var onEdit: (HomeCard) -> Void = { _ in }
    var onDelete: (HomeCard) -> Void = { _ in }

    static func == (lhs: HomeCardGrid, rhs: HomeCardGrid) -> Bool {
        lhs.cards == rhs.cards
            && lhs.usesSingleColumn == rhs.usesSingleColumn
            && lhs.spacing == rhs.spacing
    }

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
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(cards) { card in
                ReframeCardView(
                    card: card,
                    onEdit: { onEdit(card) },
                    onDelete: { onDelete(card) }
                )
            }
        }
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView()
    }
    .environmentObject(ThemeStore())
}
