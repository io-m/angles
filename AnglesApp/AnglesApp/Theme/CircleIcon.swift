import SwiftUI

struct CircleIcon: View {
    enum Size {
        case normal
        case big

        var side: CGFloat {
            switch self {
            case .normal: 40
            case .big: 52
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .normal: 17
            case .big: 21
            }
        }
    }

    var systemName: String
    var fill: Color
    var symbol: Color
    var size: Size = .normal
    var weight: Font.Weight = .medium
    var hairline: Color? = nil

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size.fontSize, weight: weight))
            .foregroundStyle(symbol)
            .frame(width: size.side, height: size.side)
            .background(fill, in: Circle())
            .overlay {
                if let hairline {
                    Circle().strokeBorder(hairline, lineWidth: 0.5)
                }
            }
            .contentShape(Circle())
    }
}

struct InitialsAvatar: View {
    var letters: String
    var side: CGFloat = 40
    var fill: Color
    var symbol: Color

    private var fontSize: CGFloat {
        side >= 48 ? 18 : 13
    }

    var body: some View {
        Text(letters)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(symbol)
            .frame(width: side, height: side)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}

enum UserInitials {
    /// Placeholder until OAuth/email exists.
    static let mockName = "Josip Miljak"

    static var letters: String {
        initials(from: mockName)
    }

    static func initials(from name: String) -> String {
        let parts = name
            .split { $0.isWhitespace || $0.isNewline }
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return String([first, second]).uppercased()
        }

        if let first = parts.first?.first {
            return String(first).uppercased()
        }

        return "Y"
    }
}
