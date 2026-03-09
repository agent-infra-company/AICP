import Foundation
import os.log

actor TaskSourceAggregator {
    private static let log = CompanionDiagnostics.logger(category: "TaskSourceAggregator")

    private var sources: [TaskSource] = []
    private var monitorTasks: [TaskSourceKind: Task<Void, Never>] = [:]
    private var currentSnapshots: [TaskSourceKind: [ExternalTaskSnapshot]] = [:]
    private var availabilityByKind: [TaskSourceKind: Bool] = [:]
    private var snapshotCountByKind: [TaskSourceKind: Int] = [:]
    private var continuation: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation?
    private var availabilityRefreshTask: Task<Void, Never>?
    private var hasStarted = false
    private let availabilityPollInterval: Duration

    nonisolated let snapshotStream: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>

    init(availabilityPollInterval: Duration = .seconds(10)) {
        self.availabilityPollInterval = availabilityPollInterval
        var cont: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation!
        self.snapshotStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func register(_ source: TaskSource) async {
        sources.append(source)
        Self.log.debug("Registered source kind=\(source.sourceKind.rawValue, privacy: .public)")
        guard hasStarted else { return }
        await startMonitoring(source)
    }

    func startAll() async {
        hasStarted = true
        Self.log.debug("Starting aggregator with \(self.sources.count) sources")
        await refreshAvailability()
        startAvailabilityRefreshLoopIfNeeded()
    }

    func stopAll() async {
        availabilityRefreshTask?.cancel()
        availabilityRefreshTask = nil
        for task in monitorTasks.values { task.cancel() }
        monitorTasks.removeAll()
        for source in sources { await source.stopMonitoring() }
        Self.log.debug("Stopped aggregator")
        continuation?.finish()
    }

    private func update(kind: TaskSourceKind, snapshots: [ExternalTaskSnapshot]) {
        let previousCount = snapshotCountByKind[kind]
        if previousCount != snapshots.count {
            Self.log.debug(
                "Snapshot count updated kind=\(kind.rawValue, privacy: .public) count=\(snapshots.count)"
            )
            snapshotCountByKind[kind] = snapshots.count
        }
        currentSnapshots[kind] = snapshots
        continuation?.yield(currentSnapshots)
    }

    private func refreshAvailability() async {
        for source in sources where monitorTasks[source.sourceKind] == nil {
            await startMonitoring(source)
        }
    }

    private func startAvailabilityRefreshLoopIfNeeded() {
        guard availabilityRefreshTask == nil else { return }

        let interval = availabilityPollInterval
        availabilityRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await self.refreshAvailability()
            }
        }
    }

    private func startMonitoring(_ source: TaskSource) async {
        let kind = source.sourceKind
        guard monitorTasks[kind] == nil else {
            return
        }

        let available = await source.isAvailable()
        let previousAvailability = availabilityByKind[kind]
        availabilityByKind[kind] = available

        if previousAvailability != available {
            if available {
                Self.log.debug("Source became available kind=\(kind.rawValue, privacy: .public)")
            } else {
                Self.log.debug("Source unavailable kind=\(kind.rawValue, privacy: .public)")
            }
        }

        guard available else {
            return
        }

        Self.log.debug("Starting monitor kind=\(kind.rawValue, privacy: .public)")
        let stream = await source.startMonitoring()
        monitorTasks[kind] = Task { [weak self] in
            for await snapshots in stream {
                guard let self else { return }
                await self.update(kind: kind, snapshots: snapshots)
            }
            Self.log.debug("Monitor stream finished kind=\(kind.rawValue, privacy: .public)")
        }
    }
}
