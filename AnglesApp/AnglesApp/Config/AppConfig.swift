import Foundation

enum AppConfig {
    static var baseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8787")!
        #else
        // TODO: replace with the Railway production URL once deployed.
        return URL(string: "https://api.angles.app")!
        #endif
    }
}
