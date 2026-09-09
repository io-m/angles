import SwiftUI

struct AccentPickerView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ColorTokens.Theme { ColorTokens.theme(colorScheme) }
    private var hsb: AccentHSB { themeStore.accentHSB }
    private var palette: AccentPalette { AccentPalette(from: hsb, colorScheme: colorScheme) }

    var body: some View {
        ModalScreen(title: "Accent") {
            VStack(spacing: 24) {
                previewBlock
                presetsBlock
                wheelBlock
            }
            .padding(.horizontal, 20)
        }
    }

    private var previewBlock: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(palette.accent)
                .frame(width: 36, height: 36)
                .overlay {
                    Circle().strokeBorder(theme.cardHairline, lineWidth: 0.5)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Contrast preview")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.muted)
                Text("Highlight")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accentDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.accentWash, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var presetsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRESETS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.muted.opacity(0.8))
                .padding(.leading, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(Array(AccentHSB.presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        themeStore.accentHSB = preset
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        hsb.matches(preset) ? theme.ink : theme.cardHairline,
                                        lineWidth: hsb.matches(preset) ? 2 : 0.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accent preset")
                    .accessibilityAddTraits(hsb.matches(preset) ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var wheelBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHEEL")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.muted.opacity(0.8))
                .padding(.leading, 16)

            VStack(spacing: 16) {
                slider("Hue", value: hueBinding, range: 0...1)
                slider("Saturation", value: saturationBinding, range: 0.15...1)
                slider("Brightness", value: brightnessBinding, range: 0.25...1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .padding(.top, 16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.muted)
            Slider(value: value, in: range)
                .tint(theme.ink)
        }
    }

    private var hueBinding: Binding<Double> {
        channelBinding(\.hue)
    }

    private var saturationBinding: Binding<Double> {
        channelBinding(\.saturation)
    }

    private var brightnessBinding: Binding<Double> {
        channelBinding(\.brightness)
    }

    private func channelBinding(_ keyPath: WritableKeyPath<AccentHSB, Double>) -> Binding<Double> {
        Binding(
            get: { hsb[keyPath: keyPath] },
            set: { newValue in
                var next = hsb
                next[keyPath: keyPath] = newValue
                themeStore.accentHSB = next
            }
        )
    }
}
