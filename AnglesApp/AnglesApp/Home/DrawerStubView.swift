import SwiftUI

struct DrawerStubView: View {
    let destination: DrawerDestination

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            Text(destination.rawValue)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        DrawerStubView(destination: .settings)
    }
}
