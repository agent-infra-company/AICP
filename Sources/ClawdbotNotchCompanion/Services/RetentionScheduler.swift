import Foundation

protocol RetentionManaging: AnyObject {
    func schedule(retentionDays: Int, onTick: @escaping @Sendable () -> Void)
}

final class RetentionScheduler: RetentionManaging {
    private var timer: Timer?

    func schedule(retentionDays: Int, onTick: @escaping @Sendable () -> Void) {
        timer?.invalidate()
        onTick()

        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60 * 24, repeats: true) { _ in
            onTick()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
