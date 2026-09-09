import SwiftUI

struct DrawerStubView: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }

    var body: some View {
        ModalScreen(title: title) {
            Text("Coming later")
                .font(.body)
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        }
    }
}

#Preview {
    DrawerStubView(title: "Subscription")
}
