import SwiftUI

struct CommandTemplatesSettingsView: View {
    @ObservedObject var core: ControlPlaneCore
    @State private var selectedTemplateId: UUID?

    var body: some View {
        Form {
            Section {
                Picker(
                    "Template set",
                    selection: Binding(
                        get: { selectedTemplateId ?? core.commandTemplateSets.first?.id ?? UUID() },
                        set: { selectedTemplateId = $0 }
                    )
                ) {
                    ForEach(core.commandTemplateSets) { set in
                        Text(set.name).tag(set.id)
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
            } header: {
                Text("Template Sets")
            } footer: {
                Text("Templates define the shell commands used to manage gateway processes.")
            }

            if let set = currentTemplateSet {
                CommandTemplateEditor(set: set) { updated in
                    core.upsertCommandTemplateSet(updated)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Command Templates")
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

    @State private var validationError: String?
    private static let placeholderPattern = #"^[a-zA-Z0-9_]+$"#

    var body: some View {
        Section("Name") {
            TextField("Template name", text: $set.name)
        }

        Section {
            cmdRow("Start", text: $set.startCmd)
            cmdRow("Stop", text: $set.stopCmd)
            cmdRow("Restart", text: $set.restartCmd)
            cmdRow("Status", text: $set.statusCmd)
        } header: {
            Text("Commands")
        } footer: {
            Text("Use {{name}} for placeholders.")
        }

        Section("Placeholders") {
            TextField(
                "host, port, gateway_url",
                text: Binding(
                    get: { set.allowedPlaceholders.joined(separator: ", ") },
                    set: {
                        set.allowedPlaceholders = $0
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                )
            )
            .font(.system(.body, design: .monospaced))

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }
        }

        Section {
            HStack {
                Spacer()
                Button("Save Template") { saveTemplate() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func cmdRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            TextField("", text: text)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func saveTemplate() {
        guard !set.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Template name cannot be empty."
            return
        }
        let invalidPlaceholders = set.allowedPlaceholders.filter {
            $0.range(of: Self.placeholderPattern, options: .regularExpression) == nil
        }
        guard invalidPlaceholders.isEmpty else {
            validationError = "Invalid: \(invalidPlaceholders.joined(separator: ", "))"
            return
        }
        validationError = nil
        onSave(set)
    }
}
