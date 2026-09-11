import SwiftUI

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
                                isSelected: draft.categories.contains(category)
                            ) {
                                toggle(category, in: &draft.categories)
                            }
                        }
                    case .moods:
                        ForEach(Emotion.allCases, id: \.self) { emotion in
                            filterRow(
                                title: emotion.displayName,
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
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.72))
                        .frame(width: 28, alignment: .center)
                        .accessibilityHidden(true)
                }

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
