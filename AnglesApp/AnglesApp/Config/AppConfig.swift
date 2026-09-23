import Foundation

enum AppConfig {
    /// `ANGLES_API_BASE_URL` in `project.yml`, per configuration. Release stays empty until the
    /// production host exists, so a Release build fails its requests instead of guessing a host.
    static let baseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AnglesAPIBaseURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw),
              url.scheme != nil,
              url.host != nil
        else {
            return nil
        }
        return url
    }()
}
