import Foundation
import os.log

actor OpenClawGatewayClient: GatewayClient {
    private static let log = CompanionDiagnostics.logger(category: "GatewayClient")
    private final class ConnectionBox {
        let socket: URLSessionWebSocketTask
        let stream: AsyncStream<GatewayEventEnvelope>
        let continuation: AsyncStream<GatewayEventEnvelope>.Continuation
        var receiveLoop: Task<Void, Never>?

        init(
            socket: URLSessionWebSocketTask,
            stream: AsyncStream<GatewayEventEnvelope>,
            continuation: AsyncStream<GatewayEventEnvelope>.Continuation
        ) {
            self.socket = socket
            self.stream = stream
            self.continuation = continuation
        }
    }

    private let session: URLSession
    private let secretStore: SecretStoring
    private var connections: [UUID: ConnectionBox] = [:]

    init(secretStore: SecretStoring, session: URLSession? = nil) {
        self.secretStore = secretStore
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 120
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    func connect(profile: ProfileConfig) async throws {
        if connections[profile.id] != nil {
            return
        }

        guard let wsURL = websocketURL(base: profile.gatewayURL, path: "/events") else {
            throw GatewayClientError.invalidURL
        }

        var request = URLRequest(url: wsURL)
        try addAuthorizationIfNeeded(to: &request, profile: profile)

        var continuation: AsyncStream<GatewayEventEnvelope>.Continuation?
        let stream = AsyncStream<GatewayEventEnvelope> { streamContinuation in
            continuation = streamContinuation
        }

        guard let continuation else {
            throw GatewayClientError.malformedResponse
        }

        let socket = session.webSocketTask(with: request)
        let box = ConnectionBox(socket: socket, stream: stream, continuation: continuation)
        connections[profile.id] = box
        socket.resume()

        Self.log.info("Connected to gateway profile=\(profile.name, privacy: .public) url=\(wsURL.absoluteString, privacy: .public)")

        box.receiveLoop = Task {
            await self.receiveMessages(profileId: profile.id, source: profile.name)
        }
    }

    func disconnect(profileId: UUID) async {
        guard let box = connections.removeValue(forKey: profileId) else {
            return
        }

        box.receiveLoop?.cancel()
        box.socket.cancel(with: .goingAway, reason: nil)
        box.continuation.finish()

        Self.log.info("Disconnected from gateway profileId=\(profileId.uuidString, privacy: .public)")
    }

    func subscribeEvents(profileId: UUID) async -> AsyncStream<GatewayEventEnvelope> {
        if let box = connections[profileId] {
            return box.stream
        }

        return AsyncStream<GatewayEventEnvelope> { continuation in
            continuation.finish()
        }
    }

    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo] {
        let (data, _) = try await requestWithFallback(
            profile: profile,
            method: "GET",
            paths: ["/routes", "/v1/routes", "/api/routes"],
            body: nil
        )

        if let direct = try? JSONDecoder().decode([RouteInfo].self, from: data), !direct.isEmpty {
            return direct
        }

        if let wrapped = try? JSONDecoder().decode(RouteEnvelope.self, from: data), !wrapped.routes.isEmpty {
            return wrapped.routes
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let routeObjects = object["routes"] as? [[String: Any]] {
            let routes = routeObjects.map { item in
                RouteInfo(
                    id: String(describing: item["id"] ?? item["name"] ?? "default"),
                    displayName: String(describing: item["displayName"] ?? item["label"] ?? item["name"] ?? "Default"),
                    metadata: (item["metadata"] as? [String: String]) ?? [:]
                )
            }
            if !routes.isEmpty {
                return routes
            }
        }

        return [RouteInfo(id: "default", displayName: "Default", metadata: [:])]
    }

    func sendTask(_ draft: TaskDraft, profile: ProfileConfig) async throws -> SentTaskInfo {
        let payload: [String: Any] = [
            "routeId": draft.routeId,
            "route_id": draft.routeId,
            "title": draft.title,
            "prompt": draft.prompt,
            "clientTaskId": draft.clientTaskId,
            "client_task_id": draft.clientTaskId
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await requestWithFallback(
            profile: profile,
            method: "POST",
            paths: ["/tasks", "/v1/tasks", "/api/tasks"],
            body: body
        )

        if let decoded = try? JSONDecoder().decode(SendTaskResponse.self, from: data) {
            return SentTaskInfo(
                taskId: decoded.taskId ?? decoded.id ?? draft.clientTaskId,
                sessionId: decoded.sessionId,
                runId: decoded.runId,
                status: decoded.status.flatMap(TaskStatus.fromGateway) ?? .queued
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let taskId = String(describing: object["taskId"] ?? object["id"] ?? draft.clientTaskId)
            let session = (object["sessionId"] ?? object["session_id"]).map { String(describing: $0) }
            let run = (object["runId"] ?? object["run_id"]).map { String(describing: $0) }
            let statusRaw = (object["status"] ?? object["state"]).map { String(describing: $0) }
            return SentTaskInfo(
                taskId: taskId,
                sessionId: session,
                runId: run,
                status: statusRaw.flatMap(TaskStatus.fromGateway) ?? .queued
            )
        }

        return SentTaskInfo(taskId: draft.clientTaskId, sessionId: nil, runId: nil, status: .queued)
    }

    func answerFollowUp(task: TaskRecord, answer: String, profile: ProfileConfig) async throws {
        let payload: [String: Any] = [
            "answer": answer,
            "response": answer,
            "runId": task.runId as Any,
            "run_id": task.runId as Any
        ]

        let body = try JSONSerialization.data(withJSONObject: payload.filter { !($0.value is NSNull) })
        let escapedTaskId = task.taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? task.taskId

        _ = try await requestWithFallback(
            profile: profile,
            method: "POST",
            paths: [
                "/tasks/\(escapedTaskId)/answer",
                "/v1/tasks/\(escapedTaskId)/answer",
                "/api/tasks/\(escapedTaskId)/answer"
            ],
            body: body
        )
    }

    private func receiveMessages(profileId: UUID, source: String) async {
        guard let box = connections[profileId] else {
            return
        }

        while !Task.isCancelled {
            do {
                let message = try await box.socket.receive()
                let event = parseEvent(message: message, source: source)
                box.continuation.yield(event)
            } catch {
                Self.log.warning("WebSocket receive error source=\(source, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                box.continuation.yield(
                    GatewayEventEnvelope(
                        source: source,
                        eventType: "connection_error",
                        payload: ["error": error.localizedDescription]
                    )
                )
                break
            }
        }

        box.continuation.finish()
        box.socket.cancel(with: .normalClosure, reason: nil)
        connections.removeValue(forKey: profileId)
    }

    private func parseEvent(message: URLSessionWebSocketTask.Message, source: String) -> GatewayEventEnvelope {
        switch message {
        case let .string(text):
            return parseEvent(jsonText: text, source: source)
        case let .data(data):
            if let text = String(data: data, encoding: .utf8) {
                return parseEvent(jsonText: text, source: source)
            }
            return GatewayEventEnvelope(source: source, eventType: "binary_event", payload: [:])
        @unknown default:
            return GatewayEventEnvelope(source: source, eventType: "unknown_event", payload: [:])
        }
    }

    private func parseEvent(jsonText: String, source: String) -> GatewayEventEnvelope {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return GatewayEventEnvelope(source: source, eventType: "message", payload: ["message": jsonText])
        }

        let payload = normalizePayload(object["payload"])
        let eventType = stringValue(for: ["eventType", "type", "event"], in: object) ?? "message"
        let taskId = stringValue(for: ["taskId", "task_id", "clientTaskId", "client_task_id"], in: object)
        let sessionId = stringValue(for: ["sessionId", "session_id"], in: object)
        let runId = stringValue(for: ["runId", "run_id"], in: object)
        let eventId = stringValue(for: ["id", "eventId", "event_id"], in: object) ?? UUID().uuidString

        return GatewayEventEnvelope(
            id: eventId,
            source: source,
            sessionId: sessionId,
            runId: runId,
            taskId: taskId ?? payload["taskId"] ?? payload["task_id"],
            eventType: eventType,
            payload: payload,
            receivedAt: Date()
        )
    }

    private func normalizePayload(_ payload: Any?) -> [String: String] {
        guard let payload else {
            return [:]
        }

        if let dict = payload as? [String: String] {
            return dict
        }

        if let dict = payload as? [String: Any] {
            var normalized: [String: String] = [:]
            for (key, value) in dict {
                normalized[key] = String(describing: value)
            }
            return normalized
        }

        return ["message": String(describing: payload)]
    }

    private func requestWithFallback(
        profile: ProfileConfig,
        method: String,
        paths: [String],
        body: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error = GatewayClientError.invalidURL

        for path in paths {
            do {
                guard let url = url(base: profile.gatewayURL, path: path) else {
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body
                if body != nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                try addAuthorizationIfNeeded(to: &request, profile: profile)

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GatewayClientError.malformedResponse
                }

                if http.statusCode == 401 || http.statusCode == 403 {
                    throw GatewayClientError.unauthorized
                }

                if (200..<300).contains(http.statusCode) {
                    return (data, http)
                }

                if http.statusCode == 404 {
                    lastError = GatewayClientError.unexpectedStatus(http.statusCode)
                    continue
                }

                throw GatewayClientError.unexpectedStatus(http.statusCode)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func addAuthorizationIfNeeded(to request: inout URLRequest, profile: ProfileConfig) throws {
        guard profile.authMode == .bearerToken,
              let tokenRef = profile.tokenRef,
              let token = try secretStore.secret(for: tokenRef),
              !token.isEmpty else {
            return
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func url(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let finalPath: String

        if basePath.isEmpty {
            finalPath = "/\(suffix)"
        } else {
            finalPath = "/\(basePath)/\(suffix)"
        }

        components.path = finalPath
        return components.url
    }

    private func websocketURL(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        default:
            components.scheme = "ws"
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components.path = "/\(suffix)"
        } else {
            components.path = "/\(basePath)/\(suffix)"
        }

        return components.url
    }

    private func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] {
                return String(describing: value)
            }
        }
        return nil
    }
}

private struct RouteEnvelope: Decodable {
    var routes: [RouteInfo]
}

private struct SendTaskResponse: Decodable {
    var id: String?
    var taskId: String?
    var sessionId: String?
    var runId: String?
    var status: String?
}

private extension TaskStatus {
    static func fromGateway(_ raw: String) -> TaskStatus? {
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "draft":
            return TaskStatus.draft
        case "queued", "pending":
            return TaskStatus.queued
        case "running", "in_progress":
            return TaskStatus.running
        case "needs_input", "question":
            return TaskStatus.needsInput
        case "completed", "done", "success":
            return TaskStatus.completed
        case "failed", "error":
            return TaskStatus.failed
        case "canceled", "cancelled":
            return TaskStatus.canceled
        case "needs_attention":
            return TaskStatus.needsAttention
        default:
            return nil
        }
    }
}
