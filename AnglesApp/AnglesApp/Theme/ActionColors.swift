import SwiftUI
import UIKit

/// The stack's three coloured actions. Rewind and Profile stay in ink.
enum ActionColors {
    /// Love: the heart button, the swipe stamp, and the list heart.
    static let love = Color(red: 1.0, green: 0.231, blue: 0.42)
    /// Pass: a cool slate blue, apart from Love's pink-red and Inspire's orange.
    static let pass = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.345, green: 0.447, blue: 0.910, alpha: 1)
                : UIColor(red: 0.357, green: 0.486, blue: 0.980, alpha: 1)
        }
    )
    /// Inspire me: the mark's own orange, for the button's glow.
    static let inspire = InspireMark.brandColor
}
