import Foundation

/// Standard interface for communicating with any agent.
/// Implement this protocol to allow AICP to send tasks and receive events from your agent.
///
/// # Adopting AgentTransport
///
/// To register a custom agent with AICP:
/// 1. Create an `AgentDescriptor` describing your agent's identity
/// 2. Implement `AgentTransport` to handle messaging
/// 3. Optionally implement `TaskSource` for passive monitoring
/// 4. Register via `AgentRegistry.register(descriptor:transport:monitor:)`
///
/// # Minimal example
/// ```swift
/// let descriptor = AgentDescriptor(
///     id: "my-agent",
///     displayName: "My Agent",
///     iconSystemName: "cpu",
///     iconColorHex: "#FF6600",
///     supportsMessaging: true,
///     endpointURL: URL(string: "http://localhost:9000")!
/// )
///
/// let transport = HTTPAgentTransport(baseURL: descriptor.endpointURL!)
/// await registry.register(descriptor: descriptor, transport: transport)
/// ```
protocol AgentTransport: AnyObject, Sendable {
    /// Unique identifier matching the AgentDescriptor.id.
    var agentId: String { get }

    /// Discover available routes/capabilities for this agent.
    func discoverRoutes() async throws -> [RouteInfo]

    /// Send a task/message to this agent.
    func sendTask(_ message: AgentMessage) async throws -> AgentResponse

    /// Answer a follow-up question from this agent.
    func answerFollowUp(taskId: String, answer: String) async throws

    /// Subscribe to real-time events from this agent.
    func subscribeEvents() async -> AsyncStream<GatewayEventEnvelope>

    /// Check if the agent is reachable.
    func isReachable() async -> Bool

    /// Connect to the agent (called before other operations).
    func connect() async throws

    /// Disconnect from the agent.
    func disconnect() async
}

/// Message sent to an agent.
struct AgentMessage: Codable, Hashable {
    var taskId: String
    var routeId: String
    var title: String
    var prompt: String
    var metadata: [String: String]

    init(
        taskId: String = UUID().uuidString,
        routeId: String = "default",
        title: String = "",
        prompt: String,
        metadata: [String: String] = [:]
    ) {
        self.taskId = taskId
        self.routeId = routeId
        self.title = title.isEmpty ? String(prompt.prefix(80)) : title
        self.prompt = prompt
        self.metadata = metadata
    }
}

/// Response from an agent after task submission.
struct AgentResponse: Codable, Hashable {
    var taskId: String
    var sessionId: String?
    var runId: String?
    var status: TaskStatus
    var message: String?
}
