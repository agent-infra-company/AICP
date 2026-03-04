import SwiftUI

struct CompanionRootView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        Group {
            if core.isExpanded {
                ExpandedCompanionView(core: core)
            } else {
                CollapsedCompanionView(core: core)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.85), value: core.isExpanded)
    }
}

private struct CollapsedCompanionView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(core.needsInputTasks.isEmpty ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text("Clawdbot")
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            Spacer(minLength: 8)

            Text("\(core.runningTasks.count) running")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !core.needsInputTasks.isEmpty {
                Text("\(core.needsInputTasks.count) input")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 340, height: 38)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            core.setExpanded(true)
        }
    }
}

private struct ExpandedCompanionView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        VStack(spacing: 10) {
            HeaderRow(core: core)

            if let lastErrorBanner = core.lastErrorBanner, !lastErrorBanner.isEmpty {
                Text(lastErrorBanner)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Picker("", selection: $core.selectedTab) {
                ForEach(CompanionCore.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            TabContent(core: core)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(width: 780, height: 560)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct HeaderRow: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        HStack(spacing: 10) {
            Text("Clawdbot Companion")
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Spacer(minLength: 8)

            profilePicker
            routePicker
            runtimeButtons

            Button {
                core.setExpanded(false)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private var profilePicker: some View {
        Picker(
            "Profile",
            selection: Binding(
                get: { core.selectedProfile?.id ?? core.profiles.first?.id ?? UUID() },
                set: { core.selectProfile($0) }
            )
        ) {
            ForEach(core.profiles) { profile in
                Text(profile.name).tag(profile.id)
            }
        }
        .frame(width: 170)
        .disabled(core.profiles.isEmpty)
    }

    private var routePicker: some View {
        let routes = core.routesByProfile[core.selectedProfile?.id ?? UUID()] ?? [RouteInfo(id: "default", displayName: "Default", metadata: [:])]

        return Picker(
            "Route",
            selection: Binding(
                get: { core.selectedRouteId },
                set: { core.selectRoute($0) }
            )
        ) {
            ForEach(routes) { route in
                Text(route.displayName).tag(route.id)
            }
        }
        .frame(width: 150)
        .disabled(core.selectedProfile == nil)
    }

    private var runtimeButtons: some View {
        HStack(spacing: 6) {
            Button("Start") {
                Task { await core.requestRuntimeAction(.start) }
            }
            .controlSize(.small)

            Button("Status") {
                Task { await core.requestRuntimeAction(.status) }
            }
            .controlSize(.small)

            Button("Restart") {
                Task { await core.requestRuntimeAction(.restart) }
            }
            .controlSize(.small)

            Button("Stop") {
                Task { await core.requestRuntimeAction(.stop) }
            }
            .controlSize(.small)
        }
        .disabled(core.selectedProfile == nil)
    }
}

private struct TabContent: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        Group {
            switch core.selectedTab {
            case .compose:
                ComposeTab(core: core)
            case .running:
                RunningTab(core: core)
            case .needsInput:
                NeedsInputTab(core: core)
            case .history:
                HistoryTab(core: core)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ComposeTab: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            TextEditor(text: $core.composePrompt)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .frame(minHeight: 260)
                .padding(8)
                .background(Color.black.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Text("Route: \(core.selectedRouteId)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Send Prompt") {
                    Task { await core.submitPrompt() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

private struct RunningTab: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        if core.runningTasks.isEmpty {
            empty("No running tasks")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(core.runningTasks) { task in
                        TaskCard(task: task, style: .running)
                    }
                }
            }
        }
    }

    private func empty(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct NeedsInputTab: View {
    @ObservedObject var core: CompanionCore
    @State private var answers: [String: String] = [:]

    var body: some View {
        if core.needsInputTasks.isEmpty {
            VStack {
                Spacer()
                Text("No pending follow-up questions")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(core.needsInputTasks) { task in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))

                            Text(task.needsInputPrompt ?? "Provide an answer")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField(
                                "Type your answer",
                                text: Binding(
                                    get: { answers[task.taskId, default: ""] },
                                    set: { answers[task.taskId] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Spacer()
                                Button("Send Answer") {
                                    let answer = answers[task.taskId, default: ""]
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !answer.isEmpty else {
                                        return
                                    }

                                    Task {
                                        await core.answerFollowUp(taskId: task.taskId, answer: answer)
                                        answers[task.taskId] = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}

private struct HistoryTab: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        if core.historyTasks.isEmpty {
            VStack {
                Spacer()
                Text("No history yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(core.historyTasks) { task in
                        TaskCard(task: task, style: .history)
                    }
                }
            }
        }
    }
}

private struct TaskCard: View {
    enum Style {
        case running
        case history
    }

    let task: TaskRecord
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Spacer()

                Text(task.status.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            if let progress = task.latestProgress {
                Text(progress)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let lastError = task.lastError {
                Text(lastError)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red)
            }

            Text(task.updatedAt, style: .time)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style == .running ? Color.blue.opacity(0.06) : Color.gray.opacity(0.1))
        )
    }

    private var statusColor: Color {
        switch task.status {
        case .completed:
            .green
        case .failed, .needsAttention:
            .red
        case .needsInput:
            .orange
        case .running, .queued:
            .blue
        case .draft, .canceled:
            .secondary
        }
    }
}
