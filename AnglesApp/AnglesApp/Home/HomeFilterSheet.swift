import SwiftUI
import UIKit

struct HomeFilterSheet: View {
    private enum FilterTab: String, CaseIterable {
        case lifeAreas
        case moods

        var title: String {
            switch self {
            case .lifeAreas: return "Life areas"
            case .moods: return "Moods"
            }
        }
    }

    let onApply: (HomeFeedFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: HomeFeedFilter
    @State private var selectedTab: FilterTab = .lifeAreas

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    init(appliedFilter: HomeFeedFilter, onApply: @escaping (HomeFeedFilter) -> Void) {
        self.onApply = onApply
        _draft = State(initialValue: appliedFilter)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter group", selection: $selectedTab) {
                    ForEach(FilterTab.allCases, id: \.self) { tab in
                        Text(tab.title)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                List {
                    switch selectedTab {
                    case .lifeAreas:
                        ForEach(ThoughtCategory.allCases, id: \.self) { category in
                            filterRow(
                                title: category.displayName,
                                systemImage: category.systemImage,
                                ink: FilterIconInk.color(for: category),
                                isSelected: draft.categories.contains(category)
                            ) {
                                toggle(category, in: &draft.categories)
                            }
                        }
                    case .moods:
                        ForEach(Emotion.allCases, id: \.self) { emotion in
                            filterRow(
                                title: emotion.displayName,
                                systemImage: emotion.systemImage,
                                ink: FilterIconInk.color(for: emotion),
                                isSelected: draft.emotions.contains(emotion)
                            ) {
                                toggle(emotion, in: &draft.emotions)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(AnglesCanvasBackground())
            .navigationTitle("Filter Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        draft = HomeFeedFilter()
                    }
                    .tint(draft.appliedCount > 0 ? .red : theme.faint)
                    .disabled(draft.appliedCount == 0)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(draft)
                        dismiss()
                    } label: {
                        if draft.appliedCount > 0 {
                            Text("Apply (\(draft.appliedCount))")
                        } else {
                            Text("Apply")
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel(
                        draft.appliedCount > 0
                            ? "Apply \(draft.appliedCount) filters"
                            : "Apply"
                    )
                }
            }
            .tint(theme.ink)
        }
    }

    private func filterRow(
        title: String,
        systemImage: String,
        ink: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
