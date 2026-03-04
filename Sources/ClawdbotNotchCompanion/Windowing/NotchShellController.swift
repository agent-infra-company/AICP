import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchShellController {
    private let core: CompanionCore
    private let panel: NotchPanel

    private var cancellables: Set<AnyCancellable> = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(core: CompanionCore) {
        self.core = core

        let initialFrame = NSRect(x: 0, y: 0, width: 340, height: 38)
        self.panel = NotchPanel(contentRect: initialFrame)
        self.panel.contentView = NSHostingView(rootView: CompanionRootView(core: core))

        bindState()
        installClickMonitors()
        updateFrame(animated: false)
        applyVisibilityPreferences()
        panel.orderFrontRegardless()
    }

    deinit {}

    func show() {
        panel.orderFrontRegardless()
    }

    private func bindState() {
        core.$isExpanded
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateFrame(animated: true)
                self.panel.orderFrontRegardless()
            }
            .store(in: &cancellables)

        core.$settings
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateFrame(animated: false)
                self.applyVisibilityPreferences()
            }
            .store(in: &cancellables)
    }

    private func applyVisibilityPreferences() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
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

    private func installClickMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleIncomingClick(point: event.locationInWindow)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleIncomingClick(point: event.locationInWindow)
            return event
        }
    }

    private func handleIncomingClick(point: NSPoint) {
        Task { @MainActor in
            guard let screen = primaryScreen else {
                return
            }

            let notchRect = notchHitRect(in: screen)
            if notchRect.contains(point) {
                core.setExpanded(true)
                panel.orderFrontRegardless()
                return
            }

            if core.isExpanded, !panel.frame.contains(point) {
                core.setExpanded(false)
            }
        }
    }

    private var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func notchHitRect(in screen: NSScreen) -> CGRect {
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

    private func updateFrame(animated: Bool) {
        guard let screen = primaryScreen else {
            return
        }

        let isExpanded = core.isExpanded
        let targetSize = CGSize(
            width: isExpanded ? 780 : 340,
            height: isExpanded ? 560 : 38
        )

        let topOffset: CGFloat = 6
        let frame = CGRect(
            x: screen.frame.midX - targetSize.width / 2,
            y: screen.frame.maxY - targetSize.height - topOffset,
            width: targetSize.width,
            height: targetSize.height
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
