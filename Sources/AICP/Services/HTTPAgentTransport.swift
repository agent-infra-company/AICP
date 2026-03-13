import Foundation
import os.log

/// Default HTTP/WebSocket transport for communicating with remote agents.
///
/// Agents that expose a standard HTTP API can be connected using this transport:
///
/// ```
/// POST /tasks       — submit a task
/// POST /tasks/:id/answer — answer a follow-up
/// GET  /routes      — discover capabilities
/// GET  /health      — health check
/// WS   /events      — real-time event stream
/// ```
///
/// All request/response bodies use JSON.
final class HTTPAgentTransport: AgentTransport, @unchecked Sendable {
    private static let log = ControlPlaneDiagnostics.logger(category: "HTTPAgentTransport")

    let agentId: String
    private let baseURL: URL
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        agentId: String,
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.agentId = agentId
        self.baseURL = baseURL
        self.session = session
    }

    func connect() async throws {
        // HTTP is stateless; nothing to connect.
    }

    func disconnect() async {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func isReachable() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    func discoverRoutes() async throws -> [RouteInfo] {
        let url = baseURL.appendingPathComponent("routes")
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode([RouteInfo].self, from: data)
    }

    func sendTask(_ message: AgentMessage) async throws -> AgentResponse {
        let url = baseURL.appendingPathComponent("tasks")
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(message)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(AgentResponse.self, from: data)
    }

    func answerFollowUp(taskId: String, answer: String) async throws {
        let url = baseURL.appendingPathComponent("tasks/\(taskId)/answer")
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["answer": answer])

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func subscribeEvents() async -> AsyncStream<GatewayEventEnvelope> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            let wsURL: URL
            if var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false) {
                components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
                wsURL = components.url ?? baseURL.appendingPathComponent("events")
            } else {
                wsURL = baseURL.appendingPathComponent("events")
            }

            let request = URLRequest(url: wsURL)

            let task = session.webSocketTask(with: request)
            self.webSocketTask = task
            task.resume()

            let readLoop = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let wsMessage = try await task.receive()
                        switch wsMessage {
                        case .string(let text):
                            if let data = text.data(using: .utf8),
                               let envelope = try? self?.decoder.decode(GatewayEventEnvelope.self, from: data) {
                                continuation.yield(envelope)
                            }
                        case .data(let data):
                            if let envelope = try? self?.decoder.decode(GatewayEventEnvelope.self, from: data) {
                                continuation.yield(envelope)
                            }
                        @unknown default:
                            break
                        }
                    } catch {
                        Self.log.debug("WebSocket read error for agent=\(self?.agentId ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
                        break
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                readLoop.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    // MARK: - Private

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AgentRegistryError.transportError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw GatewayClientError.unauthorized
            }
            throw GatewayClientError.unexpectedStatus(http.statusCode)
        }
    }
}
