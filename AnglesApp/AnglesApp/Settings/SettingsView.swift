import PhotosUI
import SwiftUI
import UserNotifications

struct SettingsView: View {
    let storeKitManager: StoreKitManager
    var identityStore: ProfileIdentityStore?

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var onLogOut: (() -> Void)? = nil
    /// Returns whether the server deleted the account. The sheet stays up until it answers.
    var onDeleteAccount: (() async -> AccountDeletion)? = nil
    var blockedPeople: [BlockedPerson] = []
    var blocksLoadState: LibraryLoadState = .loading
    var onLoadBlocks: () async -> Void = {}
    var onRetryBlocks: () -> Void = {}
    var onUnblock: (BlockedPerson) -> Void = { _ in }
    var writeError: String? = nil
    var onDismissWriteError: () -> Void = {}

    @State private var showSubscription = false
    @State private var showBlockedPeople = false
    @State private var showDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var pushStatus: UNAuthorizationStatus?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var nameFocused: Bool

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private let edgePad: CGFloat = 20

    var body: some View {
        ModalScreen(title: "Settings") {
            VStack(alignment: .leading, spacing: 0) {
                headerBlock
                    .padding(.bottom, 28)

                VStack(spacing: 0) {
                    followsRow

                    settingsRow(
                        symbol: "hand.raised",
                        title: "Blocked people",
                        subtitle: "Community safety",
                        showsDivider: false
                    ) {
                        showBlockedPeople = true
                    } trailing: {
                        EmptyView()
                    }
                }
                .padding(.bottom, 24)

                if !legalLinks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(legalLinks.enumerated()), id: \.offset) { index, link in
                            externalRow(
                                symbol: link.symbol,
                                title: link.title,
                                destination: link.destination,
                                showsDivider: index < legalLinks.count - 1,
                                beforeOpen: link.beforeOpen
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }

                VStack(spacing: 0) {
                    settingsRow(
                        symbol: "creditcard",
                        title: "Subscription",
                        subtitle: storeKitManager.settingsPlanLabel,
                        showsDivider: true
                    ) {
                        showSubscription = true
                    } trailing: {
                        EmptyView()
                    }

                    settingsRow(
                        symbol: "rectangle.portrait.and.arrow.right",
                        title: "Log out",
                        subtitle: "Returns to sign in. Does not cancel Apple.",
                        showsDivider: true
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLogOut?()
                    } trailing: {
                        EmptyView()
                    }

                    settingsRow(
                        symbol: "trash",
                        title: "Delete account",
                        subtitle: deleteAccountSubtitle,
                        showsDivider: false
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
        .task {
            await refreshPushPermission()
            await FollowPush.reconcile(notifyFollows: true)
            await refreshPushPermission()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshPushPermission() }
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

    private var showsSupportEmail: Bool {
        guard let supportMailURL = AppConfig.supportMailURL else {
            return false
        }
        return supportMailURL != AppConfig.supportContactURL
    }

    /// Hidden when `ANGLES_APP_STORE_ID` is empty. Debug does not guess an App Store page.
    private var showsRateAngles: Bool {
        AppConfig.writeReviewURL != nil
    }

    /// Ordered like Filter / People: full-width dividers between rows on sheet grey.
    private var legalLinks: [SettingsLegalLink] {
        var links: [SettingsLegalLink] = []
        if showsPrivacyPolicy {
            links.append(
                SettingsLegalLink(symbol: "lock.shield", title: "Privacy policy", destination: AppConfig.privacyPolicyURL)
            )
        }
        if showsTermsOfService {
            links.append(
                SettingsLegalLink(symbol: "doc.text", title: "Terms of service", destination: AppConfig.termsOfServiceURL)
            )
        }
        if showsSupport {
            links.append(
                SettingsLegalLink(symbol: "questionmark.bubble", title: "Support", destination: AppConfig.supportContactURL)
            )
        }
        if showsSupportEmail, let supportMailURL = AppConfig.supportMailURL,
           supportMailURL != AppConfig.supportContactURL {
            links.append(
                SettingsLegalLink(symbol: "envelope", title: "Email support", destination: supportMailURL)
            )
        }
        if showsRateAngles, let writeReviewURL = AppConfig.writeReviewURL {
            links.append(
                SettingsLegalLink(
                    symbol: "star",
                    title: "Rate Angles",
                    destination: writeReviewURL,
                    beforeOpen: { AppStoreReviewCoordinator.noteSettingsWriteReview() }
                )
            )
        }
        return links
    }

    /// Banners are an iOS permission. This row never pretends to be a switch: it asks once,
    /// then opens iOS Settings, including when already on so they can turn it off there.
    private var followsRow: some View {
        settingsRow(
            symbol: "bell",
            title: "Follows",
            subtitle: followsSubtitle,
            showsDivider: true
        ) {
            Task {
                await FollowPush.enableFromSettings()
                await refreshPushPermission()
            }
        } trailing: {
            EmptyView()
        }
        .accessibilityHint(followsAccessibilityHint)
    }

    private var followsSubtitle: String {
        guard let pushStatus else {
            return "When someone follows you"
        }
        if FollowPush.isAllowed(pushStatus) {
            return "On · iOS Settings"
        }
        if pushStatus == .denied {
            return "Allow in iOS Settings"
        }
        return "Turn on notifications"
    }

    private var followsAccessibilityHint: String {
        guard let pushStatus else {
            return "Asks iOS to allow notifications"
        }
        if pushStatus == .notDetermined {
            return "Asks iOS to allow notifications"
        }
        return "Opens iOS Settings"
    }

    private func refreshPushPermission() async {
        pushStatus = await FollowPush.authorizationStatus()
    }

    private func deleteAccount() async {
        guard !isDeletingAccount, let onDeleteAccount else {
            return
        }
        deleteAccountError = nil
        isDeletingAccount = true
        let result = await onDeleteAccount()
        isDeletingAccount = false
        if result == .failed {
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
    }

    private func settingsSymbolBadge(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.ink)
            .frame(width: 40, height: 40)
            .background(theme.ink.opacity(colorScheme == .dark ? 0.22 : 0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private func externalRow(
        symbol: String,
        title: String,
        destination: URL?,
        showsDivider: Bool,
        beforeOpen: (() -> Void)? = nil
    ) -> some View {
        settingsRow(
            symbol: symbol,
            title: title,
            subtitle: destination == nil ? "Unavailable in this build" : "Opens outside Angles",
            showsDivider: showsDivider
        ) {
            guard let destination else { return }
            beforeOpen?()
            openURL(destination)
        } trailing: {
            EmptyView()
        }
        .disabled(destination == nil)
    }

    private func settingsRow<Trailing: View>(
        symbol: String,
        title: String,
        subtitle: String,
        showsDivider: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    settingsSymbolBadge(symbol: symbol)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.ink)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(theme.muted)
                    }

                    Spacer(minLength: 8)

                    trailing()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.faint)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            if showsDivider {
                rowDivider
            }
        }
    }
}

/// One external link row for Settings; order comes from `legalLinks`.
private struct SettingsLegalLink {
    let symbol: String
    let title: String
    let destination: URL?
    var beforeOpen: (() -> Void)?

    init(symbol: String, title: String, destination: URL?, beforeOpen: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.destination = destination
        self.beforeOpen = beforeOpen
    }
}
