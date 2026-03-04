import Foundation

protocol ExternalBridge {
    var id: String { get }
    var displayName: String { get }
    func canHandle(task: TaskRecord) -> Bool
}

final class BridgeRegistry {
    private(set) var bridges: [ExternalBridge] = []

    func register(_ bridge: ExternalBridge) {
        bridges.append(bridge)
    }

    func matchingBridge(for task: TaskRecord) -> ExternalBridge? {
        bridges.first(where: { $0.canHandle(task: task) })
    }
}
