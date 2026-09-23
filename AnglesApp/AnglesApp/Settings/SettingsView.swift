import PhotosUI
import SwiftUI

struct SettingsView: View {
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    var onLogOut: (() -> Void)? = nil

    @State private var showAppearance = false
    @State private var showSubscription = false
    @State private var photoItem: PhotosPickerItem?

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private let edgePad: CGFloat = 20

    var body: some View {
        ModalScreen(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                    .padding(.bottom, 28)

                VStack(spacing: 0) {
                    cardRow(
                        symbol: "circle.lefthalf.filled",
                        title: "Appearance",
                        subtitle: themeStore.appearanceMode.title
                    ) {
                        showAppearance = true
                    } trailing: {
                        EmptyView()
                    }
                    .popover(isPresented: $showAppearance, arrowEdge: .top) {
                        AppearanceView()
                            .presentationCompactAdaptation(.popover)
                            .modifier(UserAppearance(store: themeStore))
                    }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 24)

                VStack(spacing: 0) {
                    cardRow(
                        symbol: "creditcard",
                        title: "Subscription",
                        subtitle: storeKitManager.settingsPlanLabel
                    ) {
                        showSubscription = true
                    } trailing: {
                        EmptyView()
                    }

                    rowDivider

                    cardRow(
                        symbol: "rectangle.portrait.and.arrow.right",
                        title: "Log out",
                        subtitle: "Start over on this iPhone. Does not cancel Apple."
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLogOut?()
                    } trailing: {
                        EmptyView()
                    }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, edgePad)
        }
        .sheet(isPresented: $showSubscription) {
            SubscriptionView(storeKitManager: storeKitManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.grey)
                .modifier(UserAppearance(store: themeStore))
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 12) {
            if let identityStore {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ProfileAvatar(
                        identityStore: identityStore,
                        side: 76,
                        fill: theme.ink,
                        symbol: theme.paper
                    )
                    .overlay {
                        if identityStore.isUploadingPhoto {
                            Circle()
                                .fill(theme.ink.opacity(0.45))
                            ProgressView()
                                .tint(theme.paper)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if case .saved = identityStore.photoSync {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(theme.paper, theme.ink)
                                .accessibilityLabel("Photo saved")
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.paper)
                                .frame(width: 26, height: 26)
                                .background(theme.faint, in: Circle())
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(identityStore.isUploadingPhoto)
                .accessibilityLabel("Profile photo")

                TextField(
                    "Your name",
                    text: Binding(
                        get: { identityStore.displayName },
                        set: { identityStore.updateName($0) }
                    )
                )
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    Task { await identityStore.commitName() }
                }
                .accessibilityLabel("Display name")

                if identityStore.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("On this iPhone")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(theme.muted)
                }

                if let nameSyncError = identityStore.nameSyncError {
                    Text(nameSyncError)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }

                if case .failed(let message) = identityStore.photoSync {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }

                if identityStore.photo != nil, !identityStore.isUploadingPhoto {
                    Button("Remove photo") {
                        Task { await identityStore.removePhoto() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.muted)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove profile photo")
                }
            } else {
                CircleIcon(
                    systemName: "person.fill",
                    fill: theme.ink,
                    symbol: theme.paper,
                    size: .big
                )
                .accessibilityLabel("Profile")

                Text("On this iPhone")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @MainActor
    private func loadPhoto(from item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let identityStore else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            identityStore.photoSync = .failed("Couldn't read that photo.")
            return
        }
        await identityStore.uploadPhoto(image)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.line)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func cardRow<Trailing: View>(
        symbol: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CircleIcon(systemName: symbol, fill: theme.grey, symbol: theme.faint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.ink)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(theme.muted)
                }

                Spacer(minLength: 8)

                trailing()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
