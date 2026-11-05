import SwiftUI

/// A text button in a modal title bar. Plain sits on the left, emphasis on the right,
/// destructive is the red Clear. Drawn as text, not a system bar button.
struct ModalAction {
    var title: String
    var isEnabled: Bool = true
    var role: Role = .plain
    var accessibilityLabel: String?
    var action: () -> Void

    enum Role {
        case plain
        case emphasis
        case destructive
    }
}

/// Sheet chrome. The title, text buttons, and tabs sit on the same grey as the rest of the sheet.
struct ModalScreen<Content: View>: View {
    let title: String
    var searchText: Binding<String>?
    var searchPrompt: String
    /// Pages that fill the sheet, such as the filter, scroll themselves.
    var scrolls: Bool
    var leading: ModalAction?
    var trailing: ModalAction?
    /// Stays under the title. Profile and Filter pass their tabs.
    private let header: AnyView?
    /// Pinned under the content. The consent agreement uses this.
    private let footer: AnyView?
    @ViewBuilder var content: Content

    init(
        title: String,
        searchText: Binding<String>? = nil,
        searchPrompt: String = "Search",
        scrolls: Bool = true,
        leading: ModalAction? = nil,
        trailing: ModalAction? = nil,
        header: AnyView? = nil,
        footer: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.searchText = searchText
        self.searchPrompt = searchPrompt
        self.scrolls = scrolls
        self.leading = leading
        self.trailing = trailing
        self.header = header
        self.footer = footer
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            chrome
            if scrolls {
                ScrollView {
                    content
                        .padding(.top, 12)
                        .padding(.bottom, footer == nil ? 40 : 16)
                }
                .scrollIndicators(.hidden)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if let footer {
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.grey.ignoresSafeArea())
        .tint(theme.ink)
        .presentationBackground(theme.grey)
        .presentationDragIndicator(.visible)
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            titleBar
            searchField
            if let header {
                header
            }
        }
        .padding(.bottom, 8)
    }

    private var titleBar: some View {
        ZStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                textButton(leading)
                Spacer(minLength: 0)
                textButton(trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var searchField: some View {
        if let searchText {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.faint)
                TextField(searchPrompt, text: searchText)
                    .font(.body)
                    .foregroundStyle(theme.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !searchText.wrappedValue.isEmpty {
                    Text("Clear")
                        .font(.body)
                        .foregroundStyle(theme.muted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { searchText.wrappedValue = "" }
                        .accessibilityLabel("Clear search")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(theme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func textButton(_ action: ModalAction?) -> some View {
        if let action {
            Text(action.title)
                .font(action.role == .emphasis ? .body.weight(.semibold) : .body)
                .foregroundStyle(foreground(for: action))
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard action.isEnabled else { return }
                    action.action()
                }
                .accessibilityLabel(action.accessibilityLabel ?? action.title)
                .accessibilityAddTraits(.isButton)
        }
    }

    private func foreground(for action: ModalAction) -> Color {
        guard action.isEnabled else {
            return theme.faint
        }
        switch action.role {
        case .plain:
            return theme.muted
        case .emphasis:
            return theme.ink
        case .destructive:
            return .red
        }
    }
}
