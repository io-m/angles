import SwiftUI

enum LlmModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case mistral = "mistral-small-latest"
    case gemini = "gemini-3.8-flash"
    case deepseek = "deepseek-flash"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mistral:
            return "Mistral"
        case .gemini:
            return "Gemini"
        case .deepseek:
            return "DeepSeek"
        }
    }

    var assetName: String {
        switch self {
        case .mistral:
            return "LogoMistral"
        case .gemini:
            return "LogoGemini"
        case .deepseek:
            return "LogoDeepSeek"
        }
    }

    var brandColor: Color {
        switch self {
        case .mistral:
            return Color(red: 0xFA / 255, green: 0x52 / 255, blue: 0x0F / 255)
        case .gemini:
            return Color(red: 0x8E / 255, green: 0x75 / 255, blue: 0xB2 / 255)
        case .deepseek:
            return Color(red: 0x4D / 255, green: 0x6B / 255, blue: 0xFE / 255)
        }
    }

    var brandStyle: AnyShapeStyle {
        switch self {
        case .gemini:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.98),
                        Color(red: 0.56, green: 0.46, blue: 0.90),
                        Color(red: 0.93, green: 0.42, blue: 0.58),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .mistral, .deepseek:
            return AnyShapeStyle(brandColor)
        }
    }
}

struct ModelLogo: View {
    let model: LlmModel
    var side: CGFloat = 18

    var body: some View {
        Image(model.assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: side, height: side)
            .foregroundStyle(model.brandStyle)
            .accessibilityHidden(true)
    }
}

struct ModelLogoButton: View {
    let model: LlmModel
    var fill: Color
    var hairline: Color

    var body: some View {
        ModelLogo(model: model, side: 18)
            .frame(width: 40, height: 40)
            .background(fill, in: Circle())
            .overlay {
                Circle().strokeBorder(hairline, lineWidth: 0.5)
            }
            .contentShape(Circle())
    }
}
