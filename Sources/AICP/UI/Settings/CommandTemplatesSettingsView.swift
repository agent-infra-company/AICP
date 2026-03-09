import SwiftUI

struct CommandTemplatesSettingsView: View {
    @ObservedObject var core: CompanionCore
    @State private var selectedTemplateId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Command Templates")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(
                        "Template Set",
                        selection: Binding(
                            get: { selectedTemplateId ?? core.commandTemplateSets.first?.id ?? UUID() },
                            set: { selectedTemplateId = $0 }
                        )
                    ) {
                        ForEach(core.commandTemplateSets) { set in
                            Text(set.name).tag(set.id)
                        }
                    }

                    if let set = currentTemplateSet {
                        CommandTemplateEditor(set: set) { updated in
                            core.upsertCommandTemplateSet(updated)
                        }
                    }

                    Button("Add Template Set") {
                        let newSet = CommandTemplateSet(
                            id: UUID(),
                            name: "Template \(core.commandTemplateSets.count + 1)",
                            startCmd: "openclaw gateway start --port {{port}}",
                            stopCmd: "openclaw gateway stop",
                            restartCmd: "openclaw gateway restart --port {{port}}",
                            statusCmd: "openclaw gateway status",
                            allowedPlaceholders: ["host", "port", "gateway_url", "profile_name"]
                        )
                        core.upsertCommandTemplateSet(newSet)
                        selectedTemplateId = newSet.id
                    }
                }
                .padding(8)
            }
        }
        .onAppear {
            selectedTemplateId = core.commandTemplateSets.first?.id
        }
    }

    private var currentTemplateSet: CommandTemplateSet? {
        guard let selectedTemplateId else {
            return core.commandTemplateSets.first
        }
        return core.commandTemplateSets.first(where: { $0.id == selectedTemplateId })
    }
}

struct CommandTemplateEditor: View {
    @State var set: CommandTemplateSet
    let onSave: (CommandTemplateSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Template name", text: $set.name)
            TextField("Start command", text: $set.startCmd)
            TextField("Stop command", text: $set.stopCmd)
            TextField("Restart command", text: $set.restartCmd)
            TextField("Status command", text: $set.statusCmd)

            TextField(
                "Allowed placeholders (comma separated)",
                text: Binding(
                    get: { set.allowedPlaceholders.joined(separator: ",") },
                    set: {
                        set.allowedPlaceholders = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                )
            )

            HStack {
                Spacer()
                Button("Save Template") {
                    onSave(set)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
