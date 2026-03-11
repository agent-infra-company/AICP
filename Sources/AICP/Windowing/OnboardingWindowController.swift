import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let core: ControlPlaneCore
    private var onComplete: (() -> Void)?

    init(core: ControlPlaneCore) {
        self.core = core
    }

    func showIfNeeded(onComplete: @escaping () -> Void) {
        guard !core.settings.hasCompletedOnboarding else {
            onComplete()
            return
        }
        self.onComplete = onComplete

        let contentView = OnboardingFlowView(core: core) { [weak self] in
            self?.dismiss()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to AICP"
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        self.window = window

        // Menu bar apps need explicit activation to show windows
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        core.completeOnboarding()
        let completion = onComplete
        onComplete = nil
        // Keep the onboarding window alive and hidden to avoid AppKit teardown crashes
        // during the transition into the main control-plane shell.
        window?.orderOut(nil)
        // Restore menu-bar-only mode so the Dock icon disappears
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            completion?()
        }
    }
}
