import Foundation

enum AppConfig {
    static var baseURL: URL {
        #if DEBUG
        // Physical devices cannot reach localhost; this is the Mac LAN IP.
        return URL(string: "http://192.168.0.39:8787")!
        #else
        // TODO: replace with the Railway production URL once deployed.
        return URL(string: "https://api.angles.app")!
        #endif
    }
}
