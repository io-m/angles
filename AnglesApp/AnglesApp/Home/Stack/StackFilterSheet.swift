import SwiftUI
import UIKit

struct StackFilterSheet: View {
    private enum FilterTab: String, CaseIterable, Hashable {
        case lifeAreas
        case moods

        var title: String {
            switch self {
            case .lifeAreas: return "Life areas"
            case .moods: return "Moods"
            }
        }

        var symbol: String {
            switch self {
            case .lifeAreas: return "square.grid.2x2"
            case .moods: return "face.smiling"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .lifeAreas: return "square.grid.2x2.fill"
            case .moods: return "face.smiling.fill"
            }
        }
    }

    let onApply: (StackFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: StackFilter
    @State private var selectedTab: FilterTab = .lifeAreas

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    init(appliedFilter: StackFilter, onApply: @escaping (StackFilter) -> Void) {
        self.onApply = onApply
        _draft = State(initialValue: appliedFilter)
    }

    var body: some View {
        PagingSplit(
            ids: Array(FilterTab.allCases),
            selection: $selectedTab,
            tint: { _ in theme.ink },
            label: { tab, isSelected in
                PagingTabLabel(
                    title: tab.title,
                    symbol: tab.symbol,
                    selectedSymbol: tab.selectedSymbol,
                    isSelected: isSelected,
                    tint: theme.ink
                )
            },
            page: { tab in
                rows(for: tab)
                    .padding(.top, 8)
            }
        ) { bar, pages in
            ModalScreen(
                title: "Filter Home",
                scrolls: false,
                leading: ModalAction(
                    title: "Clear",
                    isEnabled: draft.appliedCount > 0,
                    role: .destructive
                ) {
                    draft = StackFilter()
                },
                trailing: ModalAction(
                    title: draft.appliedCount > 0 ? "Apply (\(draft.appliedCount))" : "Apply",
                    role: .emphasis,
                    accessibilityLabel: draft.appliedCount > 0
                        ? "Apply \(draft.appliedCount) filters"
                        : "Apply"
                ) {
                    onApply(draft)
                    dismiss()
                },
                header: AnyView(bar)
            ) {
                pages
            }
        }
    }

    @ViewBuilder
    private func rows(for tab: FilterTab) -> some View {
        VStack(spacing: 0) {
            switch tab {
            case .lifeAreas:
                let categories = ThoughtCategory.allCases
                ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                    filterRow(
                        title: category.displayName,
                        systemImage: category.systemImage,
                        ink: FilterIconInk.color(for: category),
                        isSelected: draft.categories.contains(category),
                        showsDivider: index < categories.count - 1
                    ) {
                        toggle(category, in: &draft.categories)
                    }
                }
            case .moods:
                let emotions = Emotion.allCases
                ForEach(Array(emotions.enumerated()), id: \.element) { index, emotion in
                    filterRow(
                        title: emotion.displayName,
                        systemImage: emotion.systemImage,
                        ink: FilterIconInk.color(for: emotion),
                        isSelected: draft.emotions.contains(emotion),
                        showsDivider: index < emotions.count - 1
                    ) {
                        toggle(emotion, in: &draft.emotions)
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }

    private func filterRow(
        title: String,
        systemImage: String,
        ink: Color,
        isSelected: Bool,
        showsDivider: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ink)
                        .frame(width: 18, height: 18)
                        .frame(width: 40, height: 40)
                        .background(ink.opacity(colorScheme == .dark ? 0.22 : 0.14), in: Circle())
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.ink)

                    Spacer(minLength: 12)

                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 8)

                if showsDivider {
                    Rectangle()
                        .fill(theme.line)
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func toggle<Value: Hashable>(_ value: Value, in selection: inout Set<Value>) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}

/// Muted adaptive inks for filter badges. Same wash treatment as Subscription rows.
private enum FilterIconInk {
    static func color(for category: ThoughtCategory) -> Color {
        switch category {
        case .work:
            return ink(light: (0.18, 0.37, 0.47), dark: (0.47, 0.66, 0.78))
        case .money:
            return ink(light: (0.16, 0.46, 0.30), dark: (0.42, 0.76, 0.54))
        case .romantic:
            return ink(light: (0.70, 0.28, 0.46), dark: (0.93, 0.58, 0.72))
        case .family:
            return ink(light: (0.68, 0.40, 0.22), dark: (0.90, 0.66, 0.46))
        case .friendsSocial:
            return ink(light: (0.12, 0.46, 0.50), dark: (0.42, 0.78, 0.80))
        case .health:
            return ink(light: (0.72, 0.20, 0.24), dark: (0.93, 0.48, 0.48))
        case .selfWorth:
            return ink(light: (0.42, 0.32, 0.64), dark: (0.74, 0.66, 0.92))
        case .future:
            return ink(light: (0.71, 0.47, 0.08), dark: (0.88, 0.71, 0.34))
        case .griefLoss:
            return ink(light: (0.36, 0.42, 0.40), dark: (0.64, 0.74, 0.70))
        case .identity:
            return ink(light: (0.48, 0.34, 0.24), dark: (0.80, 0.66, 0.52))
        case .other:
            return ink(light: (0.42, 0.40, 0.36), dark: (0.74, 0.72, 0.68))
        }
    }

    static func color(for emotion: Emotion) -> Color {
        switch emotion {
        case .anger:
            return ink(light: (0.78, 0.28, 0.14), dark: (0.95, 0.55, 0.38))
        case .shame:
            return ink(light: (0.48, 0.28, 0.46), dark: (0.80, 0.58, 0.76))
        case .fear:
            return ink(light: (0.72, 0.46, 0.10), dark: (0.94, 0.74, 0.36))
        case .sadness:
            return ink(light: (0.22, 0.40, 0.62), dark: (0.52, 0.70, 0.90))
        case .envy:
            return ink(light: (0.09, 0.51, 0.40), dark: (0.28, 0.78, 0.63))
        case .loneliness:
            return ink(light: (0.30, 0.28, 0.55), dark: (0.62, 0.60, 0.88))
        case .overwhelm:
            return ink(light: (0.62, 0.28, 0.22), dark: (0.90, 0.55, 0.46))
        case .numbness:
            return ink(light: (0.40, 0.42, 0.44), dark: (0.70, 0.72, 0.74))
        case .hope:
            return ink(light: (0.78, 0.50, 0.16), dark: (0.96, 0.76, 0.42))
        }
    }

    private static func ink(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
