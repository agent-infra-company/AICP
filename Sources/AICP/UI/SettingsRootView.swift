import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case profiles = "Profiles"
    case commandTemplates = "Command Templates"
    case about = "About"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .profiles: return "person.2"
        case .commandTemplates: return "terminal"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var core: CompanionCore
    @StateObject private var updateManager = UpdateManager()

    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.iconName)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                detailContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .alert(
            core.pendingRuntimeOperation?.title ?? "",
            isPresented: Binding(
                get: { core.pendingRuntimeOperation != nil },
                set: { value in
                    if !value {
                        core.clearPendingRuntimeAction()
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                core.clearPendingRuntimeAction()
            }
            Button("Confirm", role: .destructive) {
                Task { await core.confirmPendingRuntimeAction() }
            }
        } message: {
            Text(core.pendingRuntimeOperation?.message ?? "")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .general:
            GeneralSettingsView(core: core)
        case .appearance:
            AppearanceSettingsView(core: core)
        case .profiles:
            ProfilesSettingsView(core: core)
        case .commandTemplates:
            CommandTemplatesSettingsView(core: core)
        case .about:
            AboutSettingsView(updateManager: updateManager)
        }
    }
}
