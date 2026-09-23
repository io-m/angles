import Foundation
import Observation
import SwiftUI

/// On-device profile identity, confirmed by the API. The JPEG is cached here after a
/// successful upload; the bucket copy is what cards load.
@MainActor
@Observable
final class ProfileIdentityStore {
    enum PhotoSyncState: Equatable {
        case idle
        case uploading
        case saved
        case failed(String)
    }

    private enum Keys {
        static let displayName = "angles.profileDisplayName"
        static let hasCustomName = "angles.profileNameEdited"
        static let photoFilename = "profile-photo.jpg"
    }

    var displayName: String = ""
    private(set) var hasCustomName: Bool = false
    var photo: UIImage?
    var photoSync: PhotoSyncState = .idle
    var nameSyncError: String?
    private(set) var avatarPath: String?
    private(set) var serverInitials: String = "JM"

    /// Fired after the server accepts a name or photo, so owned cards can update in place.
    var onSynced: ((String, String?) -> Void)?

    private let profileService = ProfileService()

    init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        hasCustomName = defaults.bool(forKey: Keys.hasCustomName)
        photo = Self.loadPhoto()
    }

    var profileTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "On this iPhone" : trimmed
    }

    var avatarLetters: String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UserInitials.initials(from: trimmed)
    }

    var isUploadingPhoto: Bool {
        if case .uploading = photoSync {
            return true
        }
        return false
    }

    /// TextField entry point. Marks the name as user-edited so a later Auth seed keeps it.
    func updateName(_ value: String) {
        let limited = String(value.prefix(40))
        displayName = limited
        hasCustomName = true
        UserDefaults.standard.set(limited, forKey: Keys.displayName)
        UserDefaults.standard.set(true, forKey: Keys.hasCustomName)
    }

    /// Sends the current name. Empty keeps the server initials.
    func commitName() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != displayName {
            updateName(trimmed)
        }
        nameSyncError = nil
        do {
            let profile = try await profileService.updateName(displayName)
            apply(profile)
        } catch {
            nameSyncError = "Couldn't save your name."
        }
    }

    /// Row 8 seam: fills the name from Sign in with Apple only when the user never typed one.
    func seedName(_ value: String) {
        guard !hasCustomName else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, displayName.isEmpty else { return }
        displayName = String(trimmed.prefix(40))
        UserDefaults.standard.set(displayName, forKey: Keys.displayName)
    }

    func uploadPhoto(_ image: UIImage) async {
        let previous = photo
        photoSync = .uploading
        let scaled = Self.downscaled(image)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else {
            photoSync = .failed("Couldn't read that photo.")
            return
        }

        do {
            let profile = try await profileService.uploadAvatar(jpeg: data)
            photo = scaled
            try? data.write(to: Self.photoURL, options: .atomic)
            apply(profile)
            photoSync = .saved
            try? await Task.sleep(for: .milliseconds(1200))
            if case .saved = photoSync {
                photoSync = .idle
            }
        } catch {
            photo = previous
            photoSync = .failed("Couldn't save your photo. Try again.")
        }
    }

    func removePhoto() async {
        let previous = photo
        photoSync = .uploading
        do {
            let profile = try await profileService.deleteAvatar()
            photo = nil
            try? FileManager.default.removeItem(at: Self.photoURL)
            apply(profile)
            photoSync = .saved
            try? await Task.sleep(for: .milliseconds(1200))
            if case .saved = photoSync {
                photoSync = .idle
            }
        } catch {
            photo = previous
            photoSync = .failed("Couldn't remove your photo. Try again.")
        }
    }

    private func apply(_ profile: ProfileBody) {
        serverInitials = profile.initials
        avatarPath = profile.avatarUrl
        onSynced?(profile.initials, profile.avatarUrl)
    }

    private static var photoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(Keys.photoFilename)
    }

    private static func loadPhoto() -> UIImage? {
        let url = photoURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat = 512) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Local avatar: photo when set, initials from the typed name, person icon otherwise.
/// Server cards keep `card.authorInitials`; this view is only for the local user.
struct ProfileAvatar: View {
    var identityStore: ProfileIdentityStore?
    var letters: String?
    var side: CGFloat = 40
    var fill: Color
    var symbol: Color

    var body: some View {
        if let uiImage = identityStore?.photo {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else if let resolved = identityStore?.avatarLetters ?? letters {
            InitialsAvatar(letters: resolved, side: side, fill: fill, symbol: symbol)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: side * 0.42, weight: .medium))
                .foregroundStyle(symbol)
                .frame(width: side, height: side)
                .background(fill, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

private struct ProfileIdentityKey: EnvironmentKey {
    static let defaultValue: ProfileIdentityStore? = nil
}

extension EnvironmentValues {
    var profileIdentity: ProfileIdentityStore? {
        get { self[ProfileIdentityKey.self] }
        set { self[ProfileIdentityKey.self] = newValue }
    }
}
