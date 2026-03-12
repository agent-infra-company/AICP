import Foundation
import os.log

/// Central registry for all agents — both built-in and custom.
///
/// The registry manages agent descriptors (identity/metadata), transports (messaging),
/// and monitors (passive task tracking). It provides a unified API for the rest of the
/// system to discover, track, and communicate with any agent.
///
/// # Registration Flow
///
/// ```
/// ┌─────────────┐     register()     ┌───────────────┐
/// │  Agent       │ ─────────────────► │  AgentRegistry │
/// │  Provider    │                    │                │
/// │  (you)       │ ◄───events/tasks── │  - descriptor  │
/// └─────────────┘                    │  - transport   │
///                                    │  - monitor     │
///                                    └───────────────┘
///                                           │
///                                    ┌──────┴──────┐
///                                    │ TaskSource   │  ← auto-registered
///                                    │ Aggregator   │     in aggregator
///                                    └─────────────┘
/// ```
actor AgentRegistry {
    private static let log = ControlPlaneDiagnostics.logger(category: "AgentRegistry")

    struct Registration {
        let descriptor: AgentDescriptor
        let transport: AgentTransport?
        let monitor: TaskSource?
    }

    private var registrations: [String: Registration] = [:]
    private var registrationOrder: [String] = []
    private weak var aggregator: TaskSourceAggregator?
    private var eventTasks: [String: Task<Void, Never>] = [:]

    private var continuation: AsyncStream<AgentRegistryEvent>.Continuation?
    nonisolated let eventStream: AsyncStream<AgentRegistryEvent>

    init() {
        var cont: AsyncStream<AgentRegistryEvent>.Continuation!
        self.eventStream = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    /// Set the aggregator so that registered monitors are automatically wired up.
    func setAggregator(_ aggregator: TaskSourceAggregator) {
        self.aggregator = aggregator
    }

    // MARK: - Registration

    /// Register a new agent with optional transport and monitor.
    ///
    /// - Parameters:
    ///   - descriptor: Agent identity and display metadata.
    ///   - transport: Communication channel for sending tasks/messages. Pass nil for monitor-only agents.
    ///   - monitor: TaskSource for passive task tracking. Pass nil for message-only agents.
    ///              If nil and transport is provided, a `TransportBackedTaskSource` is created automatically.
    func register(
        descriptor: AgentDescriptor,
        transport: AgentTransport? = nil,
        monitor: TaskSource? = nil
    ) async {
        let id = descriptor.id

        if registrations[id] != nil {
            Self.log.warning("Replacing existing registration for agent id=\(id, privacy: .public)")
            await unregister(agentId: id)
        }

        let effectiveMonitor: TaskSource?
        if let monitor {
            effectiveMonitor = monitor
        } else if let transport, descriptor.supportsMessaging {
            effectiveMonitor = TransportBackedTaskSource(
                agentId: id,
                transport: transport
            )
        } else {
            effectiveMonitor = nil
        }

        let registration = Registration(
            descriptor: descriptor,
            transport: transport,
            monitor: effectiveMonitor
        )

        registrations[id] = registration
        registrationOrder.append(id)

        if let monitor = effectiveMonitor, let aggregator {
            await aggregator.register(monitor)
        }

        Self.log.info("Registered agent id=\(id, privacy: .public) name=\(descriptor.displayName, privacy: .public) messaging=\(descriptor.supportsMessaging)")
        continuation?.yield(.registered(descriptor))
    }

    /// Unregister an agent and stop its monitoring/events.
    func unregister(agentId: String) async {
        guard let registration = registrations[agentId] else { return }

        eventTasks[agentId]?.cancel()
        eventTasks[agentId] = nil

        if let monitor = registration.monitor {
            await monitor.stopMonitoring()
        }

        if let transport = registration.transport {
            await transport.disconnect()
        }

        registrations[agentId] = nil
        registrationOrder.removeAll { $0 == agentId }

        Self.log.info("Unregistered agent id=\(agentId, privacy: .public)")
        continuation?.yield(.unregistered(agentId))
    }

    // MARK: - Discovery

    /// All registered agent descriptors, in registration order.
    var allDescriptors: [AgentDescriptor] {
        registrationOrder.compactMap { registrations[$0]?.descriptor }
    }

    /// Descriptors for agents that support messaging.
    var messageableDescriptors: [AgentDescriptor] {
        allDescriptors.filter(\.supportsMessaging)
    }

    /// Get descriptor for a specific agent.
    func descriptor(for agentId: String) -> AgentDescriptor? {
        registrations[agentId]?.descriptor
    }

    /// Get transport for a specific agent.
    func transport(for agentId: String) -> AgentTransport? {
        registrations[agentId]?.transport
    }

    /// Check if an agent is registered.
    func isRegistered(_ agentId: String) -> Bool {
        registrations[agentId] != nil
    }

    // MARK: - Messaging

    /// Send a message to a registered agent.
    func sendMessage(to agentId: String, message: AgentMessage) async throws -> AgentResponse {
        guard let registration = registrations[agentId] else {
            throw AgentRegistryError.agentNotFound(agentId)
        }
        guard let transport = registration.transport else {
            throw AgentRegistryError.messagingNotSupported(agentId)
        }
        guard registration.descriptor.supportsMessaging else {
            throw AgentRegistryError.messagingNotSupported(agentId)
        }

        try await transport.connect()
        return try await transport.sendTask(message)
    }

    /// Answer a follow-up from a registered agent.
    func answerFollowUp(agentId: String, taskId: String, answer: String) async throws {
        guard let registration = registrations[agentId] else {
            throw AgentRegistryError.agentNotFound(agentId)
        }
        guard let transport = registration.transport else {
            throw AgentRegistryError.messagingNotSupported(agentId)
        }

        try await transport.answerFollowUp(taskId: taskId, answer: answer)
    }

    /// Discover routes for a registered agent.
    func discoverRoutes(for agentId: String) async throws -> [RouteInfo] {
        guard let transport = registrations[agentId]?.transport else {
            throw AgentRegistryError.agentNotFound(agentId)
        }
        try await transport.connect()
        return try await transport.discoverRoutes()
    }

    /// Subscribe to events from a registered agent.
    func subscribeEvents(for agentId: String) async -> AsyncStream<GatewayEventEnvelope>? {
        guard let transport = registrations[agentId]?.transport else {
            return nil
        }
        return await transport.subscribeEvents()
    }
}

// MARK: - Events

enum AgentRegistryEvent {
    case registered(AgentDescriptor)
    case unregistered(String)
}

// MARK: - Errors

enum AgentRegistryError: Error, LocalizedError {
    case agentNotFound(String)
    case messagingNotSupported(String)
    case transportError(String)

    var errorDescription: String? {
        switch self {
        case let .agentNotFound(id):
            "Agent '\(id)' is not registered."
        case let .messagingNotSupported(id):
            "Agent '\(id)' does not support messaging."
        case let .transportError(detail):
            "Agent transport error: \(detail)"
        }
    }
}

// MARK: - Transport-backed TaskSource

/// Automatically monitors an agent via its transport's event stream.
final class TransportBackedTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind
    private let agentId: String
    private let transport: AgentTransport
    private var monitorTask: Task<Void, Never>?

    init(agentId: String, transport: AgentTransport) {
        self.agentId = agentId
        self.transport = transport
        self.sourceKind = .custom(agentId)
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        let agentId = self.agentId
        let transport = self.transport

        return AsyncStream { continuation in
            let task = Task {
                let eventStream = await transport.subscribeEvents()
                var currentTasks: [String: ExternalTaskSnapshot] = [:]

                for await event in eventStream {
                    guard !Task.isCancelled else { break }

                    let taskId = event.taskId ?? event.id
                    let status = Self.statusFromEventType(event.eventType)
                    let title = event.payload["title"] ?? event.payload["message"] ?? "Task \(taskId.prefix(8))"

                    let snapshot = ExternalTaskSnapshot(
                        id: taskId,
                        sourceKind: .custom(agentId),
                        title: title,
                        workspace: event.payload["workspace"],
                        status: status,
                        progress: event.payload["progress"],
                        needsInputPrompt: status == .needsInput ? event.payload["prompt"] : nil,
                        lastError: status == .failed ? event.payload["error"] : nil,
                        updatedAt: event.receivedAt,
                        deepLinkURL: event.payload["deepLink"].flatMap(URL.init(string:)),
                        metadata: event.payload
                    )

                    currentTasks[taskId] = snapshot
                    continuation.yield(Array(currentTasks.values))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopMonitoring() async {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func isAvailable() async -> Bool {
        await transport.isReachable()
    }

    private static func statusFromEventType(_ eventType: String) -> TaskStatus {
        switch eventType {
        case "progress", "run_progress", "working":
            .running
        case "needs_input", "question":
            .needsInput
        case "completed", "done", "success":
            .completed
        case "failed", "error":
            .failed
        case "canceled", "cancelled":
            .canceled
        case "queued", "pending":
            .queued
        default:
            .running
        }
    }
}
