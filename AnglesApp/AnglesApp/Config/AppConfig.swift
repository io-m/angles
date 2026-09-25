import Foundation

enum AppConfig {
    /// `ANGLES_API_BASE_URL` in `project.yml`, per configuration. Release stays empty until the
    /// production host exists, so a Release build fails its requests instead of guessing a host.
    static let baseURL = configuredWebURL(for: "AnglesAPIBaseURL")

    static let privacyPolicyURL = configuredWebURL(for: "AnglesPrivacyPolicyURL")
    static let termsOfServiceURL = configuredWebURL(for: "AnglesTermsOfServiceURL")
    static let supportURL = configuredWebURL(for: "AnglesSupportURL")

    static let supportEmail: String? = {
        guard let raw = configuredString(for: "AnglesSupportEmail"),
              raw.contains("@"),
              !raw.contains(where: \.isWhitespace)
        else {
            return nil
        }
        return raw
    }()

    static let supportContactURL: URL? = {
        if let supportURL {
            return supportURL
        }
        guard let supportEmail else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        return components.url
    }()

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
