import SwiftUI

private let panelWidth: CGFloat = 680
private let panelHeight: CGFloat = 280
private let glowPad: CGFloat = 60
private let windowWidth: CGFloat = panelWidth + glowPad * 2
private let windowHeight: CGFloat = panelHeight + glowPad

// animate-ui inspired spring: stiffness 200, damping 20 → response ~0.45, fraction ~0.7
private let expandSpring = Animation.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0.15)

struct CompanionRootView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        ZStack(alignment: .top) {
            if core.isExpanded {
                ExpandedCompanionView(core: core)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .offset(y: -12)),
                            removal: .scale(scale: 0.95, anchor: .top)
                                .combined(with: .opacity)
                        )
                    )
            } else {
                CollapsedCompanionView(core: core)
                    .transition(.opacity)
            }
        }
        .frame(width: windowWidth, height: windowHeight, alignment: .top)
        .animation(expandSpring, value: core.isExpanded)
    }
}

// MARK: - Collapsed Views

private struct CollapsedCompanionView: View {
    @ObservedObject var core: CompanionCore

    var body: some View {
        if core.notchDisplayInfo.hasNotch {
            NotchGradientCollapsedView(core: core)
        } else {
            PillCollapsedView(core: core)
        }
    }
}

private struct NotchOutlineShape: Shape {
    let notchWidth: CGFloat
    let wingWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let height = rect.height
        let leftEdge = wingWidth
        let rightEdge = wingWidth + notchWidth
        let cornerRadius: CGFloat = 10

        path.move(to: CGPoint(x: leftEdge, y: 0))
        path.addLine(to: CGPoint(x: leftEdge, y: height - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: leftEdge + cornerRadius, y: height),
            control: CGPoint(x: leftEdge, y: height)
        )
        path.addLine(to: CGPoint(x: rightEdge - cornerRadius, y: height))
        path.addQuadCurve(
            to: CGPoint(x: rightEdge, y: height - cornerRadius),
            control: CGPoint(x: rightEdge, y: height)
        )
        path.addLine(to: CGPoint(x: rightEdge, y: 0))

        return path
    }
}

private struct NotchGradientCollapsedView: View {
    @ObservedObject var core: CompanionCore

    private var info: NotchDisplayInfo { core.notchDisplayInfo }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slowAngle = t.remainder(dividingBy: 8) / 8 * 360
            let fastAngle = t.remainder(dividingBy: 5) / 5 * 360

            ZStack {
                NotchOutlineShape(notchWidth: info.notchWidth, wingWidth: info.wingWidth)
                    .stroke(Color.red.opacity(0.1), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                    .blur(radius: 14)

                NotchOutlineShape(notchWidth: info.notchWidth, wingWidth: info.wingWidth)
                    .stroke(Color.red.opacity(0.14), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                    .blur(radius: 10)

                NotchOutlineShape(notchWidth: info.notchWidth, wingWidth: info.wingWidth)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.red.opacity(0.4),
                                Color.red.opacity(0.06),
                                Color.red.opacity(0.35),
                                Color.red.opacity(0.06),
                                Color.red.opacity(0.4),
                            ],
                            center: UnitPoint(x: 0.5, y: 0),
                            angle: .degrees(slowAngle)
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3)

                NotchOutlineShape(notchWidth: info.notchWidth, wingWidth: info.wingWidth)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.red.opacity(0.25),
                                Color.clear,
                                Color.clear,
                                Color.red.opacity(0.25),
                                Color.clear,
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.5, y: 0),
                            angle: .degrees(-fastAngle)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 2)
            }
        }
        .frame(width: info.totalCollapsedWidth, height: info.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            core.setExpanded(true)
        }
    }
}

private struct PillCollapsedView: View {
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

// MARK: - Expanded View

private struct ExpandedCompanionView: View {
    @ObservedObject var core: CompanionCore

    private var notchTop: CGFloat {
        core.notchDisplayInfo.hasNotch ? core.notchDisplayInfo.notchHeight + 4 : 12
    }

    private var allTasks: [TaskRecord] {
        core.tasks.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slowAngle = t.remainder(dividingBy: 8) / 8 * 360
            let fastAngle = t.remainder(dividingBy: 5) / 5 * 360

            ZStack {
                // Outer ambient glow
                ExpandedNotchShape(bottomRadius: 20)
                    .stroke(Color.red.opacity(0.1), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                    .blur(radius: 14)

                // Mid ambient glow
                ExpandedNotchShape(bottomRadius: 20)
                    .stroke(Color.red.opacity(0.14), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                    .blur(radius: 10)

                // Slow rotating gradient shimmer
                ExpandedNotchShape(bottomRadius: 20)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.red.opacity(0.4),
                                Color.red.opacity(0.06),
                                Color.red.opacity(0.35),
                                Color.red.opacity(0.06),
                                Color.red.opacity(0.4),
                            ],
                            center: UnitPoint(x: 0.5, y: 0),
                            angle: .degrees(slowAngle)
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 3)

                // Fast counter-rotating highlight
                ExpandedNotchShape(bottomRadius: 20)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.red.opacity(0.25),
                                Color.clear,
                                Color.clear,
                                Color.red.opacity(0.25),
                                Color.clear,
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.5, y: 0),
                            angle: .degrees(-fastAngle)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 2)

                // Main content panel
                VStack(alignment: .leading, spacing: 10) {
                    // Top row: Avatar + ChatGPT-style input
                    HStack(alignment: .center, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.12))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "eyes")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.6))
                            )

                        HStack(spacing: 8) {
                            TextField("Message Clawdbot...", text: $core.composePrompt)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)

                            if !core.composePrompt.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button {
                                    Task { await core.submitPrompt() }
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    // Task list with staggered entrance
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            if allTasks.isEmpty {
                                StaggeredRow(index: 0) {
                                    StaticTaskRow(workspace: "signal-arena", name: "apupneja/phase4-analytics", status: "Working...", gridMode: .animated)
                                }
                                StaggeredRow(index: 1) {
                                    StaticTaskRow(workspace: "conductor", name: "apupneja/notch-chat-ui", status: "Working...", gridMode: .animated)
                                }
                                StaggeredRow(index: 2) {
                                    StaticTaskRow(workspace: "quito", name: "apupneja/fix-glow-render", status: "Queued", gridMode: .greyed)
                                }
                            } else {
                                ForEach(Array(allTasks.enumerated()), id: \.element.id) { index, task in
                                    StaggeredRow(index: index) {
                                        CompactTaskRow(task: task)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, notchTop)
                .frame(width: panelWidth, height: panelHeight)
                .background(Color.black)
                .clipShape(ExpandedNotchShape(bottomRadius: 20))
            }
            .frame(width: panelWidth, height: panelHeight)
        }
        .padding(.horizontal, glowPad)
        .frame(width: windowWidth, height: windowHeight, alignment: .top)
    }
}

// MARK: - Snake Grid Icon

private enum SnakeGridMode {
    case animated   // running — snake animation
    case greyed     // queued — all cells dim
    case solid      // completed — all cells bright
}

private struct SnakeGrid: View {
    let mode: SnakeGridMode
    let cellSize: CGFloat = 4
    let spacing: CGFloat = 1

    private let snakeOrder: [(row: Int, col: Int)] = [
        (0, 0), (0, 1), (0, 2),
        (1, 2), (2, 2),
        (2, 1), (2, 0),
        (1, 0),
    ]

    var body: some View {
        switch mode {
        case .animated:
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: 0.7) / 0.7
                grid { row, col in animatedOpacity(row: row, col: col, phase: phase) }
            }
        case .greyed:
            grid { row, col in row == 1 && col == 1 ? 0.05 : 0.2 }
        case .solid:
            grid { row, col in row == 1 && col == 1 ? 0.3 : 0.9 }
        }
    }

    private func grid(opacity: @escaping (Int, Int) -> Double) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.white.opacity(opacity(row, col)))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func animatedOpacity(row: Int, col: Int, phase: Double) -> Double {
        if row == 1 && col == 1 { return 0.05 }

        guard let index = snakeOrder.firstIndex(where: { $0.row == row && $0.col == col }) else {
            return 0.05
        }

        var adjusted = phase - Double(index) / 8.0
        if adjusted < 0 { adjusted += 1.0 }

        if adjusted < 0.125 { return 1.0 }
        else if adjusted < 0.5 { return 0.05 }
        else { return 1.0 }
    }
}

// MARK: - Task Rows

private struct StaticTaskRow: View {
    let workspace: String
    let name: String
    let status: String
    var gridMode: SnakeGridMode = .greyed

    var body: some View {
        HStack(spacing: 8) {
            SnakeGrid(mode: gridMode)

            Text(workspace)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))

            Text(name)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text(status)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct CompactTaskRow: View {
    let task: TaskRecord

    private var gridMode: SnakeGridMode {
        switch task.status {
        case .running: return .animated
        case .queued: return .greyed
        case .completed: return .solid
        default: return .greyed
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            SnakeGrid(mode: gridMode)

            Text(task.routeId)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))

            Text(task.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text(statusText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var statusText: String {
        if let progress = task.latestProgress {
            return progress
        }
        switch task.status {
        case .running: return "Working..."
        case .queued: return "Queued"
        case .needsInput: return "Needs input"
        default: return task.status.rawValue
        }
    }
}

private struct StaggeredRow<Content: View>: View {
    let index: Int
    let content: Content
    @State private var appeared = false

    init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    var body: some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(expandSpring.delay(Double(index) * 0.08)) {
                    appeared = true
                }
            }
            .onDisappear {
                appeared = false
            }
    }
}

private struct ExpandedNotchShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - bottomRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        path.addLine(to: CGPoint(x: bottomRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - bottomRadius),
            control: CGPoint(x: 0, y: rect.height)
        )
        path.closeSubpath()
        return path
    }
}
