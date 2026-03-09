import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let core: CompanionCore
    private var onComplete: (() -> Void)?

    init(core: CompanionCore) {
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: contentView)
        window.appearance = NSAppearance(named: .darkAqua)
        window.level = .floating
        window.center()

        self.window = window

        // Menu bar apps need explicit activation to show windows
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        core.completeOnboarding()
        window?.close()
        window = nil
        // Restore menu bar app behavior for the notch panel
        NSApp.setActivationPolicy(.accessory)
        onComplete?()
    }
}
