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
