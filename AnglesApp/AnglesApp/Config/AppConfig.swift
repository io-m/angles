import Foundation

enum AppConfig {
    /// `ANGLES_API_BASE_URL` in `project.yml`, per configuration. An empty value fails every
    /// request instead of guessing a host.
    static let baseURL = configuredWebURL(for: "AnglesAPIBaseURL")

    static let privacyPolicyURL = configuredWebURL(for: "AnglesPrivacyPolicyURL")
    static let termsOfServiceURL = configuredWebURL(for: "AnglesTermsOfServiceURL")
    static let supportURL = configuredWebURL(for: "AnglesSupportURL")
    /// Numeric App Store ID (`ANGLES_APP_STORE_ID`). Empty or non-numeric hides Settings → Rate Angles.
    /// Debug must not invent an ID.
    static let appStoreID: String? = {
        guard let raw = configuredString(for: "AnglesAppStoreID"), raw.allSatisfy(\.isNumber) else {
            return nil
        }
        return raw
    }()
    static let writeReviewURL: URL? = {
        guard let appStoreID else {
            return nil
        }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }()
    /// The app ships under Apple's standard licensed application EULA, not a custom one.
    static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static let supportEmail: String? = {
        guard let raw = configuredString(for: "AnglesSupportEmail"),
              raw.contains("@"),
              !raw.contains(where: \.isWhitespace)
        else {
            return nil
        }
        return raw
    }()

    static let supportMailURL: URL? = {
        guard let supportEmail else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        return components.url
    }()

    static let supportContactURL: URL? = supportURL ?? supportMailURL

    #if DEBUG
    static let isSubmissionBuild = false
    #else
    static let isSubmissionBuild = true
    #endif

    private static func configuredString(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func configuredWebURL(for key: String) -> URL? {
        guard let raw = configuredString(for: key),
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil
        else {
            return nil
        }
        return url
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Launch arguments for the Simulator demo recording (`demo/make_video.sh`). Device and
/// Release builds do not contain this, so they always go through Apple sign-in and StoreKit.
enum DemoLaunch {
    /// `-AnglesDemoSessionToken <token>`: a Better Auth session minted by `pnpm demo:session`
    /// against the local database. It is still validated by `GET /profile/session`.
    static var sessionToken: String? {
        let raw = UserDefaults.standard.string(forKey: "AnglesDemoSessionToken")
        let token = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    /// `-AnglesDemoEntitled YES`: treat the Simulator as subscribed without asking Apple.
    static var isEntitled: Bool {
        UserDefaults.standard.bool(forKey: "AnglesDemoEntitled")
    }
}
#endif
