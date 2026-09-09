import SwiftUI

struct ComposeSheetView: View {
    @ObservedObject var viewModel: HomeViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var thoughtFieldFocused: Bool

    private let chipColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                if let thought = viewModel.submittedThought,
                   let result = viewModel.submittedResult {
                    submittedConversation(thought: thought, result: result)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            composeControls
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            thoughtFieldFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text("New reframe")
                .font(.title3.bold())

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var composeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            TextField(
                "Tell me what's on your mind...",
                text: $viewModel.composeText,
                axis: .vertical
            )
            .font(.body)
            .lineLimit(3 ... 6)
            .padding(14)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .focused($thoughtFieldFocused)
            .submitLabel(.send)
            .onSubmit(submit)

            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(Style.allCases, id: \.self) { style in
                    styleChip(style)
                }
            }

            Button(action: submit) {
                Label("Send", systemImage: "arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(
                        viewModel.canSubmit
                            ? Color.accentColor
                            : Color.secondary.opacity(0.35),
                        in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func styleChip(_ style: Style) -> some View {
        let isSelected = viewModel.selectedStyle == style

        return Button {
            viewModel.selectStyle(style)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.callout)

                Text(style.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.32)
                            : Color.primary.opacity(0.08),
                        lineWidth: 0.5
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func submittedConversation(
        thought: String,
        result: ReframeResult
    ) -> some View {
        VStack(spacing: 12) {
            HStack {
                Spacer(minLength: 48)

                Text(thought)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }

            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text(result.style.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(result.reframe)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

                Spacer(minLength: 48)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func submit() {
        guard viewModel.canSubmit else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            viewModel.submitCompose()
        }
        thoughtFieldFocused = false
    }
}

#Preview {
    ComposeSheetView(viewModel: HomeViewModel())
}
