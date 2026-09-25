import PhotosUI
import SwiftUI

struct SettingsView: View {
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var onLogOut: (() -> Void)? = nil
    /// Returns whether the server deleted the account. The sheet stays up until it answers.
    var onDeleteAccount: (() async -> Bool)? = nil
    var blockedPeople: [BlockedPerson] = []
    var blocksLoadState: LibraryLoadState = .loading
    var onLoadBlocks: () async -> Void = {}
    var onRetryBlocks: () -> Void = {}
    var onUnblock: (BlockedPerson) -> Void = { _ in }
    var writeError: String? = nil
    var onDismissWriteError: () -> Void = {}

    @State private var showAppearance = false
    @State private var showSubscription = false
    @State private var showBlockedPeople = false
    @State private var showDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var nameFocused: Bool

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

                    rowDivider

                    cardRow(
                        symbol: "hand.raised",
                        title: "Blocked people",
                        subtitle: "Community safety"
                    ) {
                        showBlockedPeople = true
                    } trailing: {
                        EmptyView()
                    }
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.bottom, 24)

                if showsLegalSection {
                    VStack(spacing: 0) {
                        if showsPrivacyPolicy {
                            externalRow(
                                symbol: "lock.shield",
                                title: "Privacy policy",
                                destination: AppConfig.privacyPolicyURL
                            )
                        }

                        if showsTermsOfService {
                            if showsPrivacyPolicy {
                                rowDivider
                            }
                            externalRow(
                                symbol: "doc.text",
                                title: "Terms of service",
                                destination: AppConfig.termsOfServiceURL
                            )
                        }

                        if showsSupport {
                            if showsPrivacyPolicy || showsTermsOfService {
                                rowDivider
                            }
                            externalRow(
                                symbol: "questionmark.bubble",
                                title: "Support",
                                destination: AppConfig.supportContactURL
                            )
                        }
                    }
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.bottom, 24)
                }

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
                        subtitle: "Returns to sign in. Does not cancel Apple."
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLogOut?()
                    } trailing: {
                        EmptyView()
                    }

                    rowDivider

                    cardRow(
                        symbol: "trash",
                        title: "Delete account",
                        subtitle: deleteAccountSubtitle
                    ) {
                        guard !isDeletingAccount else {
                            return
                        }
                        showDeleteAccount = true
                    } trailing: {
                        if isDeletingAccount {
                            ProgressView()
                                .controlSize(.small)
                                .tint(theme.ink)
                        }
                    }
                    .disabled(isDeletingAccount)
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
        .sheet(isPresented: $showBlockedPeople) {
            BlockedPeopleSheet(
                people: blockedPeople,
                loadState: blocksLoadState,
                onRetry: onRetryBlocks,
                onUnblock: onUnblock,
                writeError: writeError,
                onDismissError: onDismissWriteError
            )
            .task { await onLoadBlocks() }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.grey)
            .modifier(UserAppearance(store: themeStore))
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .onDisappear {
            guard let identityStore else { return }
            Task { await identityStore.commitName() }
        }
        .alert("Delete account?", isPresented: $showDeleteAccount) {
            Button("Delete account", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Angles account and cards. It does not cancel Apple.")
        }
        .interactiveDismissDisabled(isDeletingAccount)
    }

    private var deleteAccountSubtitle: String {
        if isDeletingAccount {
            return "Deleting your account…"
        }
        return deleteAccountError ?? "Removes your Angles account and cards. Does not cancel Apple."
    }

    private var showsPrivacyPolicy: Bool {
        AppConfig.privacyPolicyURL != nil || !AppConfig.isSubmissionBuild
    }

    private var showsTermsOfService: Bool {
        AppConfig.termsOfServiceURL != nil || !AppConfig.isSubmissionBuild
    }

    private var showsSupport: Bool {
        AppConfig.supportContactURL != nil || !AppConfig.isSubmissionBuild
    }

    private var showsLegalSection: Bool {
        showsPrivacyPolicy || showsTermsOfService || showsSupport
    }

    private func deleteAccount() async {
        guard !isDeletingAccount, let onDeleteAccount else {
            return
        }
        deleteAccountError = nil
        isDeletingAccount = true
        let deleted = await onDeleteAccount()
        isDeletingAccount = false
        if !deleted {
            deleteAccountError = "Couldn't delete your account. Try again."
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 12) {
            if let identityStore {
                let isUploadingPhoto = identityStore.isUploadingPhoto
                let photoSync = identityStore.photoSync
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ProfileAvatar(
                        identityStore: identityStore,
                        side: 76,
                        fill: theme.ink,
                        symbol: theme.paper
                    )
                    .overlay {
                        if isUploadingPhoto {
                            Circle()
                                .fill(theme.ink.opacity(0.45))
                            ProgressView()
                                .tint(theme.paper)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if case .saved = photoSync {
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
                .disabled(isUploadingPhoto)
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
                .focused($nameFocused)
                .onSubmit {
                    Task { await identityStore.commitName() }
                }
                .onChange(of: nameFocused) { _, focused in
                    if !focused {
                        Task { await identityStore.commitName() }
                    }
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
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            identityStore.photoSync = .failed("Couldn't read that photo.")
            return
        }
        await identityStore.uploadPhoto(data: data)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.line)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func externalRow(symbol: String, title: String, destination: URL?) -> some View {
        cardRow(
            symbol: symbol,
            title: title,
            subtitle: destination == nil ? "Unavailable in this build" : "Opens outside Angles"
        ) {
            guard let destination else { return }
            openURL(destination)
        } trailing: {
            EmptyView()
        }
        .disabled(destination == nil)
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
