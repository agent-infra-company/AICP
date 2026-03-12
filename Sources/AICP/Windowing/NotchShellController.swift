import AppKit
import Combine
import SwiftUI

struct NotchGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenFrame: CGRect
    let isVirtual: Bool

    var wingWidth: CGFloat {
        max(80, notchWidth * 0.35)
    }

    var collapsedWindowWidth: CGFloat {
        notchWidth + 2 * wingWidth
    }
}

@MainActor
final class NotchPanelState: ObservableObject {
    @Published var displayInfo: NotchDisplayInfo
    @Published var isActiveDisplay: Bool

    init(displayInfo: NotchDisplayInfo, isActiveDisplay: Bool) {
        self.displayInfo = displayInfo
        self.isActiveDisplay = isActiveDisplay
    }
}

private struct ScreenPanelEntry {
    let screenID: CGDirectDisplayID
    let panel: NotchPanel
    let state: NotchPanelState
}

@MainActor
final class NotchShellController {
    private let core: ControlPlaneCore

    private var panelsByScreenID: [CGDirectDisplayID: ScreenPanelEntry] = [:]
    private var activeScreenID: CGDirectDisplayID?

    private var cancellables: Set<AnyCancellable> = []
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMoveMonitor: Any?
    nonisolated(unsafe) private var localMoveMonitor: Any?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    private var collapseWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var expandedAt: Date = .distantPast

    private static let expandedSize = CGSize(width: 800, height: 480)
    private static let virtualNotchWidth: CGFloat = 150
    private static let virtualNotchHeight: CGFloat = 27

    init(core: ControlPlaneCore) {
        self.core = core

        bindState()
        installClickMonitors()
        installHoverMonitors()
        installScreenObserver()
        syncPanels(for: NSEvent.mouseLocation, force: true)
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMoveMonitor {
            NSEvent.removeMonitor(globalMoveMonitor)
        }
        if let localMoveMonitor {
            NSEvent.removeMonitor(localMoveMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        syncPanels(for: NSEvent.mouseLocation, force: true)
        orderPanelsFront()
    }

    // MARK: - State Binding

    private func bindState() {
        core.$isExpanded
            .combineLatest(core.$activeToast)
            .sink { [weak self] expanded, _ in
                guard let self else { return }
                self.updatePanelInteractivity()
                self.orderPanelsFront()
                if expanded {
                    self.expandedAt = Date()
                    self.cancelCollapseTimer()
                    self.activePanel?.panel.makeKey()
                }
            }
            .store(in: &cancellables)

        core.$settings
            .sink { [weak self] _ in
                guard let self else { return }
                self.syncPanels(for: NSEvent.mouseLocation, force: true)
            }
            .store(in: &cancellables)
    }

    private func applyVisibilityPreferences() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if core.shouldShowFullscreen() {
            behavior.insert(.fullScreenAuxiliary)
        }

        for entry in panelsByScreenID.values {
            entry.panel.collectionBehavior = behavior
            entry.panel.sharingType = core.shouldHideFromScreenRecording() ? .none : .readOnly
        }
    }

    private func updatePanelInteractivity() {
        for entry in panelsByScreenID.values {
            let isExpandedOnDisplay = core.isExpanded && entry.state.isActiveDisplay
            entry.panel.ignoresMouseEvents = !isExpandedOnDisplay && core.activeToast == nil
        }
    }

    private func orderPanelsFront() {
        let orderedPanels = panelsByScreenID.values.sorted { lhs, rhs in
            if lhs.state.isActiveDisplay == rhs.state.isActiveDisplay {
                return lhs.screenID < rhs.screenID
            }
            return !lhs.state.isActiveDisplay && rhs.state.isActiveDisplay
        }

        for entry in orderedPanels {
            entry.panel.orderFrontRegardless()
        }
    }

    // MARK: - Screen Observer

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncPanels(for: NSEvent.mouseLocation, force: true)
            }
        }
    }

    // MARK: - Click Monitors

    private func installClickMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleIncomingClick(point: NSEvent.mouseLocation)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            let screenPoint: NSPoint
            if let window = event.window {
                screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            } else {
                screenPoint = NSEvent.mouseLocation
            }
            self?.handleIncomingClick(point: screenPoint)
            return event
        }
    }

    private func handleIncomingClick(point: NSPoint) {
        Task { @MainActor in
            guard let screen = resolvedScreen(for: point) else {
                return
            }

            if !core.isExpanded {
                syncPanels(preferredScreen: screen)
            }

            if core.isExpanded {
                guard let activePanel else {
                    return
                }
                if !activePanel.panel.frame.contains(point) {
                    cancelCollapseTimer()
                    core.setExpanded(false)
                } else {
                    cancelCollapseTimer()
                }
            } else {
                let notchRect = notchHitRect(in: screen)
                if notchRect.contains(point) {
                    cancelCollapseTimer()
                    core.setExpanded(true)
                    activePanel?.panel.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // MARK: - Hover Monitors

    private func installHoverMonitors() {
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved(point: NSEvent.mouseLocation)
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved(point: NSEvent.mouseLocation)
            return event
        }
    }

    private func handleMouseMoved(point: NSPoint) {
        Task { @MainActor in
            guard let screen = resolvedScreen(for: point) else { return }

            if !core.isExpanded {
                syncPanels(preferredScreen: screen)
            }

            if core.isExpanded {
                guard let activePanel else { return }
                let panelRect = activePanel.panel.frame.insetBy(dx: -10, dy: -10)
                if panelRect.contains(point) {
                    cancelCollapseTimer()
                } else {
                    startCollapseTimer()
                }
                cancelExpandTimer()
            } else {
                let hoverRect = notchHoverRect(in: screen)
                if hoverRect.contains(point) {
                    startExpandTimer()
                } else {
                    cancelExpandTimer()
                }
            }
        }
    }

    private func startExpandTimer() {
        guard expandWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expandWorkItem = nil
                self.core.setExpanded(true)
                self.orderPanelsFront()
            }
        }
        expandWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func cancelExpandTimer() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
    }

    private func startCollapseTimer() {
        guard !core.isSubmitting else { return }
        guard Date().timeIntervalSince(expandedAt) > 1.5 else { return }
        guard collapseWorkItem == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.collapseWorkItem = nil
                self.core.setExpanded(false)
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - Screen Selection

    private var activePanel: ScreenPanelEntry? {
        guard let activeScreenID else {
            return panelsByScreenID.values.first
        }
        return panelsByScreenID[activeScreenID] ?? panelsByScreenID.values.first
    }

    private var defaultScreen: NSScreen? {
        NSScreen.main
            ?? NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first(where: { screenID(for: $0) == id })
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    private func resolvedScreen(for point: NSPoint? = nil) -> NSScreen? {
        if let point, let screen = screen(containing: point) {
            return screen
        }
        if let activeScreenID, let screen = screen(for: activeScreenID) {
            return screen
        }
        return defaultScreen
    }

    private func desiredScreens(preferredScreen: NSScreen?) -> [NSScreen] {
        if core.settings.primaryDisplayOnly {
            if let preferredScreen {
                return [preferredScreen]
            }
            if let defaultScreen {
                return [defaultScreen]
            }
            return []
        }
        return NSScreen.screens
    }

    private func syncPanels(for point: NSPoint? = nil, force: Bool = false) {
        syncPanels(preferredScreen: resolvedScreen(for: point), force: force)
    }

    private func syncPanels(preferredScreen: NSScreen?, force: Bool = false) {
        let screens = desiredScreens(preferredScreen: preferredScreen)
        let desiredIDs = Set(screens.compactMap(screenID(for:)))

        let removedIDs = panelsByScreenID.keys.filter { !desiredIDs.contains($0) }
        for screenID in removedIDs {
            guard let entry = panelsByScreenID.removeValue(forKey: screenID) else { continue }
            entry.panel.orderOut(nil)
            entry.panel.close()
        }

        if let preferredScreen,
           let preferredID = screenID(for: preferredScreen),
           desiredIDs.contains(preferredID) {
            activeScreenID = preferredID
        } else if let activeScreenID, desiredIDs.contains(activeScreenID) {
            // Keep the existing active display.
        } else {
            activeScreenID = screens.compactMap(screenID(for:)).first
        }

        for screen in screens {
            guard let screenID = screenID(for: screen) else { continue }
            let displayInfo = displayInfo(for: screen)
            let isActiveDisplay = screenID == activeScreenID

            if let entry = panelsByScreenID[screenID] {
                if entry.state.displayInfo != displayInfo {
                    entry.state.displayInfo = displayInfo
                }
                if entry.state.isActiveDisplay != isActiveDisplay {
                    entry.state.isActiveDisplay = isActiveDisplay
                }
                position(entry.panel, on: screen)
            } else {
                let state = NotchPanelState(displayInfo: displayInfo, isActiveDisplay: isActiveDisplay)
                let panel = makePanel(state: state)
                position(panel, on: screen)
                panelsByScreenID[screenID] = ScreenPanelEntry(
                    screenID: screenID,
                    panel: panel,
                    state: state
                )
            }
        }

        updateActiveDisplayInfo()
        applyVisibilityPreferences()
        updatePanelInteractivity()
        orderPanelsFront()
    }

    private func makePanel(state: NotchPanelState) -> NotchPanel {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: Self.expandedSize.width,
            height: Self.expandedSize.height
        )
        let panel = NotchPanel(contentRect: initialFrame)
        panel.contentView = NSHostingView(rootView: ControlPlaneRootView(core: core, panelState: state))
        return panel
    }

    // MARK: - Notch Geometry

    private func detectNotchGeometry(screen: NSScreen) -> NotchGeometry? {
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - leftArea.width - rightArea.width + 4
            if notchWidth > 0, notchWidth < screen.frame.width * 0.5 {
                let notchHeight = max(screen.safeAreaInsets.top, min(leftArea.height, rightArea.height), 38)
                return NotchGeometry(
                    notchWidth: notchWidth,
                    notchHeight: notchHeight,
                    screenFrame: screen.frame,
                    isVirtual: false
                )
            }
        }

        if screen.safeAreaInsets.top > 0 {
            let estimatedNotchWidth: CGFloat = 210
            return NotchGeometry(
                notchWidth: estimatedNotchWidth,
                notchHeight: max(screen.safeAreaInsets.top, 38),
                screenFrame: screen.frame,
                isVirtual: false
            )
        }

        guard core.settings.virtualNotchEnabled else {
            return nil
        }

        return NotchGeometry(
            notchWidth: Self.virtualNotchWidth,
            notchHeight: Self.virtualNotchHeight,
            screenFrame: screen.frame,
            isVirtual: true
        )
    }

    private func notchGeometry(for screen: NSScreen) -> NotchGeometry? {
        detectNotchGeometry(screen: screen)
    }

    private func displayInfo(for screen: NSScreen) -> NotchDisplayInfo {
        if let geo = notchGeometry(for: screen) {
            return NotchDisplayInfo(
                hasNotch: true,
                isVirtualNotch: geo.isVirtual,
                notchWidth: geo.notchWidth,
                notchHeight: geo.notchHeight,
                wingWidth: geo.wingWidth,
                totalCollapsedWidth: geo.collapsedWindowWidth
            )
        }
        return .noNotch
    }

    private func notchHitRect(in screen: NSScreen) -> CGRect {
        if let geo = notchGeometry(for: screen) {
            let padding: CGFloat = 20
            return CGRect(
                x: screen.frame.midX - (geo.collapsedWindowWidth / 2) - padding,
                y: screen.frame.maxY - geo.notchHeight - padding,
                width: geo.collapsedWindowWidth + 2 * padding,
                height: geo.notchHeight + padding
            )
        }

        let frame = screen.frame
        let width = min(max(frame.width * 0.22, 260), 420)
        let height: CGFloat = 60
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func notchHoverRect(in screen: NSScreen) -> CGRect {
        if let geo = notchGeometry(for: screen) {
            let widthPadding: CGFloat = 8
            let activationWidth = geo.notchWidth + 2 * widthPadding
            let activationHeight = min(max(geo.notchHeight + 2, 24), 40)
            return CGRect(
                x: screen.frame.midX - activationWidth / 2,
                y: screen.frame.maxY - activationHeight,
                width: activationWidth,
                height: activationHeight
            )
        }

        let frame = screen.frame
        let width = min(max(frame.width * 0.14, 180), 280)
        let activationHeight: CGFloat = 32
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - activationHeight,
            width: width,
            height: activationHeight
        )
    }

    // MARK: - Window Positioning

    private func position(_ panel: NotchPanel, on screen: NSScreen) {
        let size = Self.expandedSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    private func updateActiveDisplayInfo() {
        core.notchDisplayInfo = activePanel?.state.displayInfo ?? .noNotch
    }
}
