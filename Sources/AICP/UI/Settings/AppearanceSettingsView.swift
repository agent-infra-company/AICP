import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var core: ControlPlaneCore

    private let presetColors: [(name: String, hex: String)] = [
        ("Red", "#FF0000"),
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Green", "#30D158"),
        ("Orange", "#FF9500"),
        ("Teal", "#5AC8FA"),
    ]

    var body: some View {
        Form {
            Section("Notch Style") {
                Picker("Style", selection: Binding(
                    get: { core.settings.notchStyle },
                    set: { newValue in core.updateSetting { $0.notchStyle = newValue } }
                )) {
                    ForEach(NotchStyle.allCases) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            if core.settings.notchStyle != .hidden {
                Section("Glow Color") {
                    HStack(spacing: 10) {
                        ForEach(presetColors, id: \.hex) { preset in
                            AccentCircleButton(
                                isSelected: core.settings.glowColorHex == preset.hex,
                                color: Color(hex: preset.hex)
                            ) {
                                core.updateSetting { $0.glowColorHex = preset.hex }
                            }
                            .help(preset.name)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Preview") {
                    glowPreview
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .animation(.easeInOut(duration: 0.2), value: core.settings.notchStyle)
    }

    private var glowPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)
                .frame(height: 44)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .darkGray))
                .frame(width: 160, height: 26)

            if core.settings.notchStyle == .glow {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: core.settings.glowColorHex).opacity(0.25))
                    .frame(width: 160, height: 26)
                    .blur(radius: 10)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(hex: core.settings.glowColorHex).opacity(0.8), lineWidth: 1.5)
                    .frame(width: 160, height: 26)
                    .shadow(color: Color(hex: core.settings.glowColorHex).opacity(0.6), radius: 8)
            } else if core.settings.notchStyle == .subtle {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(hex: core.settings.glowColorHex).opacity(0.3), lineWidth: 1)
                    .frame(width: 160, height: 26)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0)
                        .padding(2)
                )
                .shadow(
                    color: isSelected ? color.opacity(0.4) : .clear,
                    radius: isSelected ? 4 : 0
                )
        }
        .buttonStyle(.plain)
    }
}
