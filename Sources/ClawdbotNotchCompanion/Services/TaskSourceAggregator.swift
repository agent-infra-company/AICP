import Foundation

actor TaskSourceAggregator {
    private var sources: [TaskSource] = []
    private var monitorTasks: [TaskSourceKind: Task<Void, Never>] = [:]
    private var currentSnapshots: [TaskSourceKind: [ExternalTaskSnapshot]] = [:]
    private var continuation: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation?
    private var hasStarted = false

    nonisolated let snapshotStream: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>

    init() {
        var cont: AsyncStream<[TaskSourceKind: [ExternalTaskSnapshot]]>.Continuation!
        self.snapshotStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    func register(_ source: TaskSource) async {
        sources.append(source)
        guard hasStarted else { return }
        await startMonitoring(source)
    }

    func startAll() async {
        hasStarted = true
        print("[TaskSourceAggregator] startAll with \(sources.count) sources")
        for source in sources {
            await startMonitoring(source)
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

    private func startMonitoring(_ source: TaskSource) async {
        let kind = source.sourceKind
        guard monitorTasks[kind] == nil else {
            print("[TaskSourceAggregator] \(kind.rawValue) already monitoring, skipping")
            return
        }
        let available = await source.isAvailable()
        guard available else {
            print("[TaskSourceAggregator] \(kind.rawValue) not available, skipping")
            return
        }

        print("[TaskSourceAggregator] Starting \(kind.rawValue)")
        let stream = await source.startMonitoring()
        monitorTasks[kind] = Task { [weak self] in
            for await snapshots in stream {
                guard let self else { return }
                await self.update(kind: kind, snapshots: snapshots)
            }
        }
    }
}
