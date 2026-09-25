import Foundation

/// Exactly one funnel screen owns the window at a time.
enum AppDestination: Equatable, CustomStringConvertible {
    case launching
    case login
    case taste
    case paywall
    case home

    var description: String {
        switch self {
        case .launching: return "launching"
        case .login: return "login"
        case .taste: return "taste"
        case .paywall: return "paywall"
        case .home: return "home"
        }
    }
}

/// Every input the funnel reads, taken from one synchronous snapshot so no frame can
/// combine a cleared flag with a stale one.
struct AppGateInputs: Equatable {
    var sessionRestored: Bool
    var entitlementsReady: Bool
    var isSignedIn: Bool
    /// Apple's current answer for this account: never the launch cache before StoreKit is
    /// ready, never while the local session is signed out.
    var isEntitled: Bool
    /// Server taste consumed-or-completed state. There is no install-local taste flag.
    var serverTasteCompleted: Bool
    /// Taste "Renew membership" opened the paywall before the taste was saved.
    var membershipRequested: Bool
}

enum AppGate {
    static func resolve(_ inputs: AppGateInputs) -> AppDestination {
        guard inputs.sessionRestored, inputs.entitlementsReady else {
            return .launching
        }
        guard inputs.isSignedIn else {
            return .login
        }
        if inputs.isEntitled {
            return .home
        }
        if inputs.serverTasteCompleted || inputs.membershipRequested {
            return .paywall
        }
        return .taste
    }
}
