import AppKit
import Combine
import SwiftUI

struct NotchGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenFrame: CGRect

    var wingWidth: CGFloat {
        max(80, notchWidth * 0.35)
    }

    var collapsedWindowWidth: CGFloat {
        notchWidth + 2 * wingWidth
    }
}

@MainActor
final class NotchShellController {
    private let core: CompanionCore
    private let panel: NotchPanel

    private var cancellables: Set<AnyCancellable> = []
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMoveMonitor: Any?
    nonisolated(unsafe) private var localMoveMonitor: Any?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    private var cachedNotchGeo: NotchGeometry?
    private var cachedScreenFrame: CGRect = .zero

    private var collapseWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?

    private static let expandedSize = CGSize(width: 800, height: 340)

    init(core: CompanionCore) {
        self.core = core

        let initialFrame = NSRect(x: 0, y: 0, width: Self.expandedSize.width, height: Self.expandedSize.height)
        self.panel = NotchPanel(contentRect: initialFrame)
        self.panel.contentView = NSHostingView(rootView: CompanionRootView(core: core))

        bindState()
        installClickMonitors()
        installHoverMonitors()
        installScreenObserver()
        positionWindow()
        updateNotchInfo()
        applyVisibilityPreferences()
        panel.orderFrontRegardless()
        NotchSpace.shared.addWindow(panel)
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
        panel.orderFrontRegardless()
    }

    // MARK: - State Binding

    private func bindState() {
        core.$isExpanded
            .sink { [weak self] expanded in
                guard let self else { return }
                self.panel.orderFrontRegardless()
                if expanded {
                    self.panel.makeKey()
                }
            }
            .store(in: &cancellables)

        core.$settings
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyVisibilityPreferences()
            }
            .store(in: &cancellables)
    }

    private func applyVisibilityPreferences() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if core.shouldShowFullscreen() {
            behavior.insert(.fullScreenAuxiliary)
        }
        panel.collectionBehavior = behavior

        if core.shouldHideFromScreenRecording() {
            panel.sharingType = .none
        } else {
            panel.sharingType = .readOnly
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
                self.cachedNotchGeo = nil
                self.cachedScreenFrame = .zero
                self.positionWindow()
                self.updateNotchInfo()
                self.applyVisibilityPreferences()
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
            guard let screen = primaryScreen else {
                return
            }

            if core.isExpanded {
                if !panel.frame.contains(point) {
                    cancelCollapseTimer()
                    core.setExpanded(false)
                } else {
                    // User clicked inside the panel — cancel any pending collapse
                    cancelCollapseTimer()
                }
            } else {
                let notchRect = notchHitRect(in: screen)
                if notchRect.contains(point) {
                    cancelCollapseTimer()
                    core.setExpanded(true)
                    panel.makeKeyAndOrderFront(nil)
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
            guard let screen = primaryScreen else { return }

            if core.isExpanded {
                let panelRect = panel.frame.insetBy(dx: -10, dy: -10)
                if panelRect.contains(point) {
                    cancelCollapseTimer()
                } else {
                    startCollapseTimer()
                }
                // Cancel any pending expand if mouse left the notch zone
                cancelExpandTimer()
            } else {
                let hoverRect = notchHitRect(in: screen)
                if hoverRect.contains(point) {
                    // Start expand timer — must hold for 2s
                    startExpandTimer()
                } else {
                    // Mouse left the notch zone — cancel pending expand
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
                self.panel.orderFrontRegardless()
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

    // MARK: - Notch Geometry

    private var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func notchGeometry(for screen: NSScreen) -> NotchGeometry? {
        if screen.frame == cachedScreenFrame, let cached = cachedNotchGeo {
            return cached
        }
        let geo = detectNotchGeometry(screen: screen)
        cachedNotchGeo = geo
        cachedScreenFrame = screen.frame
        return geo
    }

    private func detectNotchGeometry(screen: NSScreen) -> NotchGeometry? {
        guard screen.safeAreaInsets.top > 0 else {
            return nil
        }

        let notchHeight = screen.safeAreaInsets.top

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - leftArea.width - rightArea.width + 4
            if notchWidth > 0, notchWidth < screen.frame.width * 0.5 {
                return NotchGeometry(
                    notchWidth: notchWidth,
                    notchHeight: notchHeight,
                    screenFrame: screen.frame
                )
            }
        }

        let estimatedNotchWidth: CGFloat = 210
        return NotchGeometry(
            notchWidth: estimatedNotchWidth,
            notchHeight: notchHeight,
            screenFrame: screen.frame
        )
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
        } else {
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
    }

    // MARK: - Window Positioning

    private func positionWindow() {
        guard let screen = primaryScreen else {
            return
        }

        let size = Self.expandedSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    private func updateNotchInfo() {
        guard let screen = primaryScreen else {
            return
        }
        if let geo = notchGeometry(for: screen) {
            core.notchDisplayInfo = NotchDisplayInfo(
                hasNotch: true,
                notchWidth: geo.notchWidth,
                notchHeight: geo.notchHeight,
                wingWidth: geo.wingWidth,
                totalCollapsedWidth: geo.collapsedWindowWidth
            )
        } else {
            core.notchDisplayInfo = .noNotch
        }
    }
}
