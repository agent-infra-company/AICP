import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var core: ControlPlaneCore
    @StateObject private var updateManager = UpdateManager()

    @State private var selectedTab: String = "General"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.accentColor)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettingsView(core: core)
                case "Appearance":
                    AppearanceSettingsView(core: core)
                case "About":
                    AboutSettingsView(updateManager: updateManager)
                default:
                    GeneralSettingsView(core: core)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 420)
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
}

func customBadge(text: String) -> some View {
    Text(text)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(Color(nsColor: .secondarySystemFill))
        )
}
