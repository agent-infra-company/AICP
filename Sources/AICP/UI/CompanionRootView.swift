import SwiftUI
import AppKit

private let panelWidth: CGFloat = 680
private let panelHeight: CGFloat = 280
private let glowPad: CGFloat = 60
private let windowWidth: CGFloat = panelWidth + glowPad * 2
private let windowHeight: CGFloat = panelHeight + glowPad
private let avatarWidth: CGFloat = 140
private let rolodexRowHeight: CGFloat = 36
private let rolodexPeekHeight: CGFloat = 22
private let rolodexVisibleRows: Int = 3
private let rolodexViewportHeight: CGFloat = (rolodexRowHeight * CGFloat(rolodexVisibleRows)) + (rolodexPeekHeight * 2)
private let viewAllButtonHeight: CGFloat = 30
private let fullListPanelHeight: CGFloat = 420
private let fullListVisibleRows: Int = 6

// animate-ui inspired spring: stiffness 200, damping 20 → response ~0.45, fraction ~0.7
private let expandSpring = Animation.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0.15)

private struct SampleRolodexTask {
    let workspace: String
    let name: String
    let status: String
    let gridMode: SnakeGridMode
}

private let sampleRolodexTasks: [SampleRolodexTask] = [
    .init(workspace: "signal-arena", name: "apupneja/phase4-analytics", status: "Working...", gridMode: .animated),
    .init(workspace: "conductor", name: "apupneja/notch-chat-ui", status: "Working...", gridMode: .animated),
    .init(workspace: "quito", name: "apupneja/fix-glow-render", status: "Queued", gridMode: .greyed),
    .init(workspace: "loom", name: "apupneja/calendar-sync", status: "Working...", gridMode: .animated),
    .init(workspace: "ferry", name: "apupneja/api-v2-migrate", status: "Queued", gridMode: .greyed),
]

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
        .frame(width: windowWidth, height: core.showingFullTaskList ? fullListPanelHeight + glowPad : windowHeight, alignment: .top)
        .animation(expandSpring, value: core.isExpanded)
        .animation(expandSpring, value: core.showingFullTaskList)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: core.activeToast)
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
    var notchWidth: CGFloat
    var wingWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(notchWidth, wingWidth) }
        set {
            notchWidth = newValue.first
            wingWidth = newValue.second
        }
    }

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
    @State private var toastExpanded = false

    private var info: NotchDisplayInfo { core.notchDisplayInfo }
    private var glowColor: Color { Color(hex: core.settings.glowColorHex) }
    private var intensityMultiplier: Double {
        switch core.settings.notchStyle {
        case .glow: return 1.0
        case .subtle: return 0.5
        case .hidden: return 0.0
        }
    }

    private var effectiveNotchWidth: CGFloat {
        toastExpanded ? toastExpandedWidth : info.notchWidth
    }

    private var effectiveWingWidth: CGFloat {
        toastExpanded ? 0 : info.wingWidth
    }

    private var effectiveTotalWidth: CGFloat {
        toastExpanded ? toastExpandedWidth : info.totalCollapsedWidth
    }

    var body: some View {
        ZStack(alignment: .top) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let slowAngle = t.remainder(dividingBy: 8) / 8 * 360
                let fastAngle = t.remainder(dividingBy: 5) / 5 * 360

                ZStack {
                    if core.settings.notchStyle != .hidden {
                        NotchOutlineShape(notchWidth: effectiveNotchWidth, wingWidth: effectiveWingWidth)
                            .stroke(glowColor.opacity(0.1 * intensityMultiplier), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                            .blur(radius: 14)

                        NotchOutlineShape(notchWidth: effectiveNotchWidth, wingWidth: effectiveWingWidth)
                            .stroke(glowColor.opacity(0.14 * intensityMultiplier), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                            .blur(radius: 10)

                        NotchOutlineShape(notchWidth: effectiveNotchWidth, wingWidth: effectiveWingWidth)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        glowColor.opacity(0.4 * intensityMultiplier),
                                        glowColor.opacity(0.06 * intensityMultiplier),
                                        glowColor.opacity(0.35 * intensityMultiplier),
                                        glowColor.opacity(0.06 * intensityMultiplier),
                                        glowColor.opacity(0.4 * intensityMultiplier),
                                    ],
                                    center: UnitPoint(x: 0.5, y: 0),
                                    angle: .degrees(slowAngle)
                                ),
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                            )
                            .blur(radius: 3)

                        NotchOutlineShape(notchWidth: effectiveNotchWidth, wingWidth: effectiveWingWidth)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        glowColor.opacity(0.25 * intensityMultiplier),
                                        Color.clear,
                                        Color.clear,
                                        glowColor.opacity(0.25 * intensityMultiplier),
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
            }
            .frame(width: effectiveTotalWidth, height: info.notchHeight)

            // Toast content overlay
            if let toast = core.activeToast {
                HStack(spacing: 0) {
                    // Left wing: avatar + scrolling marquee
                    HStack(spacing: 8) {
                        RiveAvatarView()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                        MarqueeText(
                            text: toast.title,
                            font: .system(size: 13, weight: .medium),
                            color: .white.opacity(0.9),
                            speed: 30,
                            minimumCharacterCount: toastMarqueeCharacterThreshold
                        )
                    }
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                    // Gap matching the hardware notch
                    Color.clear
                        .frame(width: info.notchWidth)

                    // Right wing: status label
                    Text(toastStatusLabel(toast.status))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                        .padding(.trailing, 14)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .opacity(toastExpanded ? 1 : 0)
                .frame(width: effectiveNotchWidth, height: info.notchHeight)
                .background(Color.black)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: toastBottomRadius,
                        bottomTrailingRadius: toastBottomRadius,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
                .contentShape(Rectangle())
                .onTapGesture { core.handleToastTap() }
            }
        }
        .frame(width: toastExpandedWidth, height: info.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if core.activeToast != nil {
                core.handleToastTap()
            } else {
                core.setExpanded(true)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: toastExpanded)
        .onChange(of: core.activeToast) { _, newToast in
            if newToast != nil {
                toastExpanded = true
            } else {
                toastExpanded = false
            }
        }
    }
}

private func cliPickerLabel(_ cli: TaskSourceKind) -> String {
    switch cli {
    case .claudeCode: return "Claude"
    case .codex: return "Codex"
    case .openClaw: return "OpenClaw"
    default: return cli.displayName
    }
}

private func cliSubmissionHint(_ cli: TaskSourceKind) -> String? {
    switch cli {
    case .claudeCode, .codex:
        return "Launches a new CLI session and copies the prompt to the clipboard for pasting."
    default:
        return nil
    }
}

private func toastStatusLabel(_ status: TaskStatus) -> String {
    switch status {
    case .completed: return "Done"
    case .failed: return "Error"
    case .needsInput: return "Needs input"
    case .needsAttention: return "Attention"
    case .running: return "Working..."
    default: return "Updated"
    }
}

private struct PillCollapsedView: View {
    @ObservedObject var core: CompanionCore
    @State private var toastExpanded = false

    private var currentWidth: CGFloat {
        toastExpanded ? toastExpandedWidth : 340
    }

    var body: some View {
        ZStack {
            if core.activeToast == nil {
                HStack(spacing: 10) {
                    Circle()
                        .fill(core.allNeedsInputCount == 0 ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text("AICP")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Spacer(minLength: 8)

                    Text("\(core.allRunningCount) running")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    if core.allNeedsInputCount > 0 {
                        Text("\(core.allNeedsInputCount) input")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            if let toast = core.activeToast {
                HStack(spacing: 8) {
                    RiveAvatarView()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    MarqueeText(
                        text: toast.title,
                        font: .system(size: 13, weight: .medium),
                        color: .white.opacity(0.9),
                        speed: 30,
                        minimumCharacterCount: toastMarqueeCharacterThreshold
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    Text(toastStatusLabel(toast.status))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .opacity(toastExpanded ? 1 : 0)
                .transition(.opacity)
            }
        }
        .frame(width: currentWidth, height: 38)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if core.activeToast != nil {
                core.handleToastTap()
            } else {
                core.setExpanded(true)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: toastExpanded)
        .onChange(of: core.activeToast) { _, newToast in
            if newToast != nil {
                toastExpanded = true
            } else {
                toastExpanded = false
            }
        }
    }
}

// MARK: - Expanded View

private struct ExpandedCompanionView: View {
    @ObservedObject var core: CompanionCore

    private var notchTop: CGFloat {
        core.notchDisplayInfo.hasNotch ? core.notchDisplayInfo.notchHeight : 0
    }

    private var displayTasks: [DisplayTask] {
        core.notchDisplayTasks
    }

    private var currentPanelHeight: CGFloat {
        core.showingFullTaskList ? fullListPanelHeight : panelHeight
    }

    private var glowColor: Color { Color(hex: core.settings.glowColorHex) }
    private var intensityMultiplier: Double {
        switch core.settings.notchStyle {
        case .glow: return 1.0
        case .subtle: return 0.5
        case .hidden: return 0.0
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let slowAngle = t.remainder(dividingBy: 8) / 8 * 360
            let fastAngle = t.remainder(dividingBy: 5) / 5 * 360

            ZStack {
                if core.settings.notchStyle != .hidden {
                    // Outer ambient glow
                    ExpandedNotchShape(bottomRadius: 20)
                        .stroke(glowColor.opacity(0.1 * intensityMultiplier), style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                        .blur(radius: 14)

                    // Mid ambient glow
                    ExpandedNotchShape(bottomRadius: 20)
                        .stroke(glowColor.opacity(0.14 * intensityMultiplier), style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
                        .blur(radius: 10)

                    // Slow rotating gradient shimmer
                    ExpandedNotchShape(bottomRadius: 20)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    glowColor.opacity(0.4 * intensityMultiplier),
                                    glowColor.opacity(0.06 * intensityMultiplier),
                                    glowColor.opacity(0.35 * intensityMultiplier),
                                    glowColor.opacity(0.06 * intensityMultiplier),
                                    glowColor.opacity(0.4 * intensityMultiplier),
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
                                    glowColor.opacity(0.25 * intensityMultiplier),
                                    Color.clear,
                                    Color.clear,
                                    glowColor.opacity(0.25 * intensityMultiplier),
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

                // Main content panel
                HStack(spacing: 0) {
                    // Left column: Rive avatar spanning full height below notch
                    RiveAvatarView()
                        .frame(width: avatarWidth, height: currentPanelHeight - notchTop)
                        .clipped()
                        .padding(.top, notchTop)

                    // Right column: input + rolodex tasks or full list
                    if core.showingFullTaskList {
                        FullTaskListView(core: core) {
                            withAnimation(expandSpring) {
                                core.showingFullTaskList = false
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                        .padding(.top, notchTop)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            // ChatGPT-style input with inline CLI picker
                            HStack(spacing: 8) {
                                TextField("Make things happen...", text: $core.composePrompt)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                                    .onSubmit {
                                        Task { await core.submitPrompt() }
                                    }

                                if core.availableCLIs.count > 1 {
                                    Menu {
                                        ForEach(core.availableCLIs, id: \.rawValue) { cli in
                                            Button {
                                                core.selectCLI(cli)
                                            } label: {
                                                HStack {
                                                    Text(cli.displayName)
                                                    if cli == core.selectedCLI {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Text(cliPickerLabel(core.selectedCLI))
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                }

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
                            .padding(.bottom, 4)

                            if let hint = cliSubmissionHint(core.selectedCLI) {
                                Text(hint)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 8)
                            }

                            // Rolodex task list (3 visible rows + top/bottom peeks)
                            if displayTasks.isEmpty {
                                RolodexTaskList(itemCount: sampleRolodexTasks.count) { index in
                                    let task = sampleRolodexTasks[index]
                                    StaticTaskRow(
                                        workspace: task.workspace,
                                        name: task.name,
                                        status: task.status,
                                        gridMode: task.gridMode
                                    )
                                    .frame(height: rolodexRowHeight)
                                }
                            } else {
                                RolodexTaskList(
                                    itemCount: displayTasks.count,
                                    onTapIndex: { index in
                                        core.openTask(displayTasks[index])
                                    }
                                ) { index in
                                    UnifiedTaskRow(task: displayTasks[index])
                                        .frame(height: rolodexRowHeight)
                                }
                            }

                            // View All button
                            Button {
                                withAnimation(expandSpring) {
                                    core.showingFullTaskList = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("View All Tasks")
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .frame(height: viewAllButtonHeight)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                        .padding(.top, notchTop)
                    }
                }
                .frame(width: panelWidth, height: currentPanelHeight)
                .background(Color.black)
                .clipShape(ExpandedNotchShape(bottomRadius: 20))
            }
            .frame(width: panelWidth, height: currentPanelHeight)
        }
        .padding(.horizontal, glowPad)
        .frame(width: windowWidth, height: currentPanelHeight + glowPad, alignment: .top)
        .animation(expandSpring, value: core.showingFullTaskList)
    }
}

// MARK: - Rolodex Task List

private struct RolodexTaskList<RowContent: View>: View {
    let itemCount: Int
    let rowContent: (Int) -> RowContent
    let onTapIndex: (Int) -> Void

    @State private var topVisibleIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var wheelAccumulator: CGFloat = 0

    private let maxStepPerGesture = 4

    init(
        itemCount: Int,
        onTapIndex: @escaping (Int) -> Void = { _ in },
        @ViewBuilder rowContent: @escaping (Int) -> RowContent
    ) {
        self.itemCount = max(itemCount, 1)
        self.onTapIndex = onTapIndex
        self.rowContent = rowContent
    }

    private var maxTopVisibleIndex: Int {
        max(0, itemCount - rolodexVisibleRows)
    }

    private var baseOffset: CGFloat {
        -(rolodexRowHeight - rolodexPeekHeight)
    }

    private var clampedDragOffset: CGFloat {
        min(max(dragOffset, -rolodexRowHeight), rolodexRowHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(-1...rolodexVisibleRows, id: \.self) { relative in
                rowSlot(relative: relative)
            }
        }
        .offset(y: baseOffset + clampedDragOffset)
        .frame(height: rolodexViewportHeight, alignment: .top)
        .clipped()
        .background(
            ScrollWheelCaptureView { deltaY in
                handleScrollWheel(deltaY: deltaY)
            }
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    completeDrag(value)
                }
        )
        .animation(.interactiveSpring(response: 0.26, dampingFraction: 0.84), value: topVisibleIndex)
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.88), value: dragOffset)
        .onChange(of: itemCount) { _, _ in
            topVisibleIndex = clampedTopIndex(topVisibleIndex)
            wheelAccumulator = 0
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.22), location: 0),
                        .init(color: .white.opacity(0.6), location: 0.4),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: rolodexPeekHeight)

                Rectangle()

                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.6), location: 0.6),
                        .init(color: .white.opacity(0.22), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: rolodexPeekHeight)
            }
        )
    }

    private func completeDrag(_ value: DragGesture.Value) {
        let predictedTravel = value.predictedEndTranslation.height
        var steps = Int(round(-predictedTravel / rolodexRowHeight))

        if steps == 0 {
            if value.translation.height <= -(rolodexRowHeight / 2) {
                steps = 1
            } else if value.translation.height >= (rolodexRowHeight / 2) {
                steps = -1
            }
        }

        steps = min(max(steps, -maxStepPerGesture), maxStepPerGesture)

        if steps != 0 {
            _ = applyStep(steps)
        }

        dragOffset = 0
    }

    private func handleScrollWheel(deltaY: CGFloat) {
        guard itemCount > 1 else { return }

        wheelAccumulator += deltaY
        let threshold = rolodexRowHeight / 2

        while abs(wheelAccumulator) >= threshold {
            if wheelAccumulator > 0 {
                if applyStep(-1) {
                    wheelAccumulator -= threshold
                } else {
                    wheelAccumulator = 0
                    break
                }
            } else {
                if applyStep(1) {
                    wheelAccumulator += threshold
                } else {
                    wheelAccumulator = 0
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func rowSlot(relative: Int) -> some View {
        let index = topVisibleIndex + relative
        if (0..<itemCount).contains(index) {
            rowContent(index)
                .frame(height: rolodexRowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapIndex(index)
                }
                .opacity((relative == -1 || relative == rolodexVisibleRows) ? 0.58 : 1)
                .scaleEffect((relative == -1 || relative == rolodexVisibleRows) ? 0.98 : 1, anchor: .center)
        } else {
            Color.clear
                .frame(height: rolodexRowHeight)
        }
    }

    private func clampedTopIndex(_ rawIndex: Int) -> Int {
        min(max(rawIndex, 0), maxTopVisibleIndex)
    }

    private func applyStep(_ step: Int) -> Bool {
        let next = clampedTopIndex(topVisibleIndex + step)
        guard next != topVisibleIndex else { return false }
        topVisibleIndex = next
        return true
    }
}

private struct ScrollWheelCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        removeEventMonitor()
    }

    private func updateEventMonitor() {
        removeEventMonitor()

        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }

            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else {
                return event
            }

            self.onScroll?(event.scrollingDeltaY)
            return nil
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
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

private struct UnifiedTaskRow: View {
    let task: DisplayTask

    private var gridMode: SnakeGridMode {
        switch task.status {
        case .running: return .animated
        case .queued: return .greyed
        case .completed: return .solid
        default: return .greyed
        }
    }

    private var sourceColor: Color {
        switch task.sourceKind {
        case .openClaw: return .blue
        case .conductor: return .purple
        case .claudeCode: return .green
        case .codex: return .teal
        case .claudeDesktop: return .orange
        case .cursor: return .indigo
        case .webAIChat: return .cyan
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            SnakeGrid(mode: gridMode)

            Image(systemName: task.sourceKind.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(sourceColor.opacity(0.8))
                .frame(width: 14)

            if let workspace = task.workspace {
                Text(workspace)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text(task.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text(task.statusText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(task.status == .needsInput ? Color.orange.opacity(0.7) : .white.opacity(0.4))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

// MARK: - Full Task List View

private struct FullTaskListView: View {
    @ObservedObject var core: CompanionCore
    let onBack: () -> Void

    private let pageSize = 20

    @State private var visibleCount = 20

    private var allTasks: [DisplayTask] {
        core.allDisplayTasksIncludingTerminal
    }

    private var visibleTasks: [DisplayTask] {
        Array(allTasks.prefix(visibleCount))
    }

    private var hasMore: Bool {
        visibleCount < allTasks.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack(spacing: 6) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(allTasks.count) tasks")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
                .background(Color.white.opacity(0.1))

            // Scrollable task list
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        UnifiedTaskRow(task: task)
                            .frame(height: rolodexRowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                core.openTask(task)
                            }
                    }

                    if hasMore {
                        Button {
                            visibleCount += pageSize
                        } label: {
                            Text("Load more...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Toast Constants & Marquee

private let toastExpandedWidth: CGFloat = 480
private let toastBottomRadius: CGFloat = 14
private let toastMarqueeCharacterThreshold = 8

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let speed: Double
    let minimumCharacterCount: Int

    @State private var textWidth: CGFloat = 0
    @State private var animationStart = Date()
    private let gap: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            let shouldScroll = text.count > minimumCharacterCount && textWidth > 0

            if shouldScroll {
                let totalCycle = textWidth + gap
                let duration = max(totalCycle / max(speed, 1), 0.1)
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(animationStart)
                    let phase = elapsed.truncatingRemainder(dividingBy: duration)
                    let scrollOffset = -(phase / duration) * totalCycle
                    HStack(spacing: gap) {
                        marqueeLabel
                        marqueeLabel
                    }
                    .offset(x: scrollOffset)
                }
                .frame(width: available, alignment: .leading)
                .clipped()
            } else {
                marqueeLabel
                    .frame(width: available, alignment: .leading)
            }
        }
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            animationStart = .now
        }
        .onChange(of: text) { _, _ in
            animationStart = .now
        }
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { textWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in textWidth = w }
                }
            )
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
