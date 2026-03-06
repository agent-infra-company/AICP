import Foundation

actor TaskSourceAggregator {
    private var sources: [TaskSource] = []
    private var monitorTasks: [TaskSourceKind: Task<Void, Never>] = [:]
    private var currentSnapshots: [TaskSourceKind: [ExternalTaskSnapshot]] = [:]
    private var continuation: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation?

    nonisolated let snapshotStream: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>

    init() {
        var cont: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation!
        self.snapshotStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func register(_ source: TaskSource) {
        sources.append(source)
    }

    func startAll() async {
        for source in sources {
            let kind = source.sourceKind
            guard await source.isAvailable() else { continue }

            let stream = await source.startMonitoring()
            monitorTasks[kind] = Task { [weak self] in
                for await snapshots in stream {
                    guard let self else { return }
                    await self.update(kind: kind, snapshots: snapshots)
                }
            }
        }
    }

    func stopAll() async {
        for task in monitorTasks.values { task.cancel() }
        monitorTasks.removeAll()
        for source in sources { await source.stopMonitoring() }
        continuation?.finish()
    }

    private func update(kind: TaskSourceKind, snapshots: [ExternalTaskSnapshot]) {
        currentSnapshots[kind] = snapshots
        continuation?.yield(currentSnapshots)
    }
}
