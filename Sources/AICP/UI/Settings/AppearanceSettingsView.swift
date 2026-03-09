import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var core: CompanionCore

    private let presetColors: [(name: String, hex: String)] = [
        ("Red", "#FF0000"),
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
        ("Green", "#30D158"),
        ("Orange", "#FF9500"),
        ("Teal", "#5AC8FA"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance")
                .font(.title2.weight(.semibold))

            GroupBox("Notch Glow") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Style", selection: Binding(
                        get: { core.settings.notchStyle },
                        set: { newValue in core.updateSetting { $0.notchStyle = newValue } }
                    )) {
                        ForEach(NotchStyle.allCases) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    if core.settings.notchStyle != .hidden {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Glow Color")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 12) {
                                ForEach(presetColors, id: \.hex) { preset in
                                    Circle()
                                        .fill(Color(hex: preset.hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(.white, lineWidth: core.settings.glowColorHex == preset.hex ? 2.5 : 0)
                                        )
                                        .shadow(color: core.settings.glowColorHex == preset.hex ? Color(hex: preset.hex).opacity(0.5) : .clear, radius: 6)
                                        .contentShape(Circle())
                                        .onTapGesture {
                                            core.updateSetting { $0.glowColorHex = preset.hex }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }
}
