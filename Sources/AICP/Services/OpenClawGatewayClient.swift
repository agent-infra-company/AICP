import CryptoKit
import Foundation
import os.log

/// Outgoing request frame: {type:"req", id, method, params}
private struct RequestFrame: Encodable {
    let type = "req"
    let id: String
    let method: String
    let params: [String: AnyCodable]?
}

/// Minimal type-erased Encodable wrapper for building request params.
private struct AnyCodable: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Int: try container.encode(v)
        case let v as Int64: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [String: AnyCodable]:
            try container.encode(v)
        case let v as [AnyCodable]:
            try container.encode(v)
        default:
            try container.encode(String(describing: value))
        }
    }
}

/// Thread-safe wrapper for JSON dictionaries crossing actor boundaries.
private final class JSONBox: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}

private final class PendingResponse: @unchecked Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<JSONBox, Error>)
        case finished(Result<JSONBox, Error>)
    }

    private let lock = NSLock()
    private var state: State = .idle

    func wait() async throws -> JSONBox {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }

            switch state {
            case let .finished(result):
                continuation.resume(with: result)
            case .idle:
                state = .waiting(continuation)
            case .waiting:
                continuation.resume(throwing: GatewayClientError.protocolError("Duplicate pending response waiter"))
            }
        }
    }

    func succeed(_ value: JSONBox) {
        finish(.success(value))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<JSONBox, Error>) {
        lock.lock()
        let state = self.state
        switch state {
        case .finished:
            lock.unlock()
            return
        case .idle:
            self.state = .finished(result)
            lock.unlock()
        case let .waiting(continuation):
            self.state = .finished(result)
            lock.unlock()
            continuation.resume(with: result)
        }
    }
}

private final class ChallengeWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var nonce: String?
    private var continuation: CheckedContinuation<String?, Never>?

    func wait(timeout: TimeInterval) async -> String? {
        if let nonce = lock.withLock({ nonce }) {
            return nonce
        }

        return await withTaskGroup(of: String?.self) { group in
            group.addTask { [self] in
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if let nonce {
                        lock.unlock()
                        continuation.resume(returning: nonce)
                    } else {
                        self.continuation = continuation
                        lock.unlock()
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(Int(timeout * 1000)))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            cancelPendingContinuation()
            return result
        }
    }

    func resolve(_ nonce: String?) {
        lock.lock()
        self.nonce = nonce
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: nonce)
    }

    private func cancelPendingContinuation() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: nil)
    }
}

private struct PendingRequest {
    let response: PendingResponse
    let timeoutTask: Task<Void, Never>
}

private struct DeviceIdentity {
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKeyData: Data
    let publicKey: String
    let id: String
}

private struct ConnectAuthContext {
    let params: [String: AnyCodable]?
    let tokenForSignature: String
    let deviceTokenRef: String
}

private enum GatewayCredentialMode {
    case token
    case password
}

private struct GatewayCredential {
    let mode: GatewayCredentialMode
    let value: String
}

actor OpenClawGatewayClient: GatewayClient {
    private static let log = ControlPlaneDiagnostics.logger(category: "GatewayClient")

    private final class ConnectionBox {
        let socket: URLSessionWebSocketTask
        let eventStream: AsyncStream<GatewayEventEnvelope>
        let eventContinuation: AsyncStream<GatewayEventEnvelope>.Continuation
        let profileName: String

        var receiveLoop: Task<Void, Never>?
        var pending: [String: PendingRequest] = [:]
        let challengeWaiter = ChallengeWaiter()

        init(
            socket: URLSessionWebSocketTask,
            eventStream: AsyncStream<GatewayEventEnvelope>,
            eventContinuation: AsyncStream<GatewayEventEnvelope>.Continuation,
            profileName: String
        ) {
            self.socket = socket
            self.eventStream = eventStream
            self.eventContinuation = eventContinuation
            self.profileName = profileName
        }
    }

    private let session: URLSession
    private let secretStore: SecretStoring
    private let deviceIdentity: DeviceIdentity
    private let clientInstanceId: String

    private var connections: [UUID: ConnectionBox] = [:]

    init(secretStore: SecretStoring, session: URLSession? = nil) {
        self.secretStore = secretStore
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 300
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
        self.deviceIdentity = Self.loadOrCreateDeviceIdentity(secretStore: secretStore)
        self.clientInstanceId = Self.loadOrCreateClientInstanceId(secretStore: secretStore)
    }

    func connect(profile: ProfileConfig) async throws {
        if connections[profile.id] != nil {
            return
        }

        let websocketPaths = ["/", "/events"]
        var lastError: Error = GatewayClientError.invalidURL

        for websocketPath in websocketPaths {
            do {
                try await connect(profile: profile, websocketPath: websocketPath)
                return
            } catch {
                lastError = error
                Self.log.warning(
                    "Gateway connect failed profile=\(profile.name, privacy: .public) path=\(websocketPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                await disconnect(profileId: profile.id)
            }
        }

        throw lastError
    }

    private func connect(profile: ProfileConfig, websocketPath: String) async throws {
        guard let wsURL = websocketURL(base: profile.gatewayURL, path: websocketPath) else {
            throw GatewayClientError.invalidURL
        }

        let socket = session.webSocketTask(with: URLRequest(url: wsURL))

        var continuation: AsyncStream<GatewayEventEnvelope>.Continuation?
        let stream = AsyncStream<GatewayEventEnvelope> { c in
            continuation = c
        }
        guard let continuation else {
            throw GatewayClientError.malformedResponse
        }

        let box = ConnectionBox(
            socket: socket,
            eventStream: stream,
            eventContinuation: continuation,
            profileName: profile.name
        )
        connections[profile.id] = box
        socket.resume()

        Self.log.info(
            "WebSocket opened for profile=\(profile.name, privacy: .public) path=\(websocketPath, privacy: .public) url=\(wsURL.absoluteString, privacy: .public)"
        )

        box.receiveLoop = Task { [weak self] in
            await self?.receiveLoop(profileId: profile.id)
        }

        do {
            try await performHandshake(profileId: profile.id, profile: profile)
            Self.log.info("Handshake complete for profile=\(profile.name, privacy: .public)")
        } catch {
            await disconnect(profileId: profile.id)
            throw error
        }
    }

    func disconnect(profileId: UUID) async {
        guard let box = connections.removeValue(forKey: profileId) else { return }
        box.receiveLoop?.cancel()
        box.challengeWaiter.resolve(nil)
        box.socket.cancel(with: .goingAway, reason: nil)
        box.eventContinuation.finish()
        failPendingRequests(in: box, error: GatewayClientError.connectionFailed("Disconnected"))
        Self.log.info("Disconnected profileId=\(profileId.uuidString, privacy: .public)")
    }

    func subscribeEvents(profileId: UUID) async -> AsyncStream<GatewayEventEnvelope> {
        if let box = connections[profileId] {
            return box.eventStream
        }
        return AsyncStream { $0.finish() }
    }

    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo] {
        if connections[profile.id] == nil {
            do {
                try await connect(profile: profile)
            } catch {
                Self.log.warning(
                    "Gateway connect for agents.list failed, falling back to HTTP: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if connections[profile.id] != nil {
            do {
                let result = try await sendRequest(profileId: profile.id, method: "agents.list", params: nil)
                return parseRoutes(from: result)
            } catch {
                Self.log.warning("WS agents.list failed: \(error.localizedDescription, privacy: .public)")
            }

            do {
                let legacy = try await sendRequest(profileId: profile.id, method: "routes.list", params: nil)
                return parseRoutes(from: legacy)
            } catch {
                Self.log.warning("WS routes.list failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let (data, _) = try await httpRequest(
            profile: profile,
            method: "GET",
            paths: ["/api/agents", "/agents", "/v1/agents", "/api/routes", "/routes", "/v1/routes"],
            body: nil
        )
        return parseRoutesFromJSON(data)
    }

    func sendTask(_ draft: TaskDraft, profile: ProfileConfig) async throws -> SentTaskInfo {
        let agentId = normalizedAgentId(from: draft.routeId)
        let sessionKey = sessionKey(for: agentId)

        if connections[profile.id] != nil {
            do {
                let result = try await sendRequest(
                    profileId: profile.id,
                    method: "chat.send",
                    params: [
                        "sessionKey": AnyCodable(sessionKey),
                        "message": AnyCodable(draft.prompt),
                        "thinking": AnyCodable("low"),
                        "timeoutMs": AnyCodable(30000),
                        "idempotencyKey": AnyCodable(draft.clientTaskId),
                    ]
                )
                Self.log.info(
                    "Submitted prompt via WS chat.send profile=\(profile.name, privacy: .public) sessionKey=\(sessionKey, privacy: .public)"
                )
                return parseSentTaskInfo(from: result, fallbackId: draft.clientTaskId, defaultSessionId: sessionKey)
            } catch {
                Self.log.warning("WS chat.send failed, trying agent: \(error.localizedDescription, privacy: .public)")
            }

            do {
                let result = try await sendRequest(
                    profileId: profile.id,
                    method: "agent",
                    params: buildAgentParams(draft: draft, agentId: agentId, sessionKey: sessionKey)
                )
                Self.log.info(
                    "Submitted prompt via WS agent profile=\(profile.name, privacy: .public) sessionKey=\(sessionKey, privacy: .public)"
                )
                return parseSentTaskInfo(from: result, fallbackId: draft.clientTaskId, defaultSessionId: sessionKey)
            } catch {
                Self.log.warning("WS agent failed, trying legacy tasks.create: \(error.localizedDescription, privacy: .public)")
            }

            do {
                let legacyResult = try await sendRequest(
                    profileId: profile.id,
                    method: "tasks.create",
                    params: [
                        "routeId": AnyCodable(draft.routeId),
                        "title": AnyCodable(draft.title),
                        "prompt": AnyCodable(draft.prompt),
                        "clientTaskId": AnyCodable(draft.clientTaskId),
                    ]
                )
                Self.log.info(
                    "Submitted prompt via WS tasks.create profile=\(profile.name, privacy: .public) route=\(draft.routeId, privacy: .public)"
                )
                return parseSentTaskInfo(from: legacyResult, fallbackId: draft.clientTaskId, defaultSessionId: sessionKey)
            } catch {
                Self.log.warning(
                    "WS tasks.create failed, falling back to HTTP: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let payload: [String: Any] = [
            "routeId": draft.routeId,
            "route_id": draft.routeId,
            "title": draft.title,
            "prompt": draft.prompt,
            "clientTaskId": draft.clientTaskId,
            "client_task_id": draft.clientTaskId,
            "agentId": agentId,
            "agent_id": agentId,
            "sessionKey": sessionKey,
            "session_key": sessionKey,
            "message": draft.prompt,
            "idempotencyKey": draft.clientTaskId,
            "idempotency_key": draft.clientTaskId,
            "timeoutMs": 30000,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await httpRequest(
            profile: profile,
            method: "POST",
            paths: ["/hooks/chat/send", "/hooks/agent", "/api/tasks", "/tasks", "/v1/tasks"],
            body: body
        )
        Self.log.info(
            "Submitted prompt via HTTP profile=\(profile.name, privacy: .public) sessionKey=\(sessionKey, privacy: .public)"
        )
        return parseSentTaskInfoFromJSON(data, fallbackId: draft.clientTaskId, defaultSessionId: sessionKey)
    }

    func answerFollowUp(task: TaskRecord, answer: String, profile: ProfileConfig) async throws {
        let sessionKey = task.sessionId ?? self.sessionKey(for: normalizedAgentId(from: task.routeId))

        if connections[profile.id] != nil {
            do {
                _ = try await sendRequest(
                    profileId: profile.id,
                    method: "chat.send",
                    params: [
                        "sessionKey": AnyCodable(sessionKey),
                        "message": AnyCodable(answer),
                        "thinking": AnyCodable("low"),
                        "timeoutMs": AnyCodable(30000),
                        "idempotencyKey": AnyCodable(UUID().uuidString),
                    ]
                )
                Self.log.info(
                    "Submitted follow-up via WS chat.send profile=\(profile.name, privacy: .public) sessionKey=\(sessionKey, privacy: .public)"
                )
                return
            } catch {
                Self.log.warning("WS chat.send failed, trying legacy tasks.answer: \(error.localizedDescription, privacy: .public)")
            }

            do {
                _ = try await sendRequest(
                    profileId: profile.id,
                    method: "tasks.answer",
                    params: [
                        "taskId": AnyCodable(task.taskId),
                        "answer": AnyCodable(answer),
                        "runId": AnyCodable(task.runId ?? ""),
                    ]
                )
                return
            } catch {
                Self.log.warning(
                    "WS tasks.answer failed, falling back to HTTP: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let payload: [String: Any] = [
            "answer": answer,
            "response": answer,
            "runId": task.runId as Any,
            "run_id": task.runId as Any,
            "message": answer,
            "sessionKey": sessionKey,
            "session_key": sessionKey,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload.filter { !($0.value is NSNull) })
        let escapedTaskId = task.taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? task.taskId
        _ = try await httpRequest(
            profile: profile,
            method: "POST",
            paths: [
                "/hooks/chat/send",
                "/api/tasks/\(escapedTaskId)/answer",
                "/tasks/\(escapedTaskId)/answer",
                "/v1/tasks/\(escapedTaskId)/answer",
            ],
            body: body
        )
    }

    private func performHandshake(profileId: UUID, profile: ProfileConfig) async throws {
        let authContext = authContext(for: profile)
        let challengeNonce = await waitForChallenge(profileId: profileId, timeout: 5)

        let modernParams = try buildModernConnectParams(profile: profile, authContext: authContext, nonce: challengeNonce)
        do {
            let result = try await sendRequest(profileId: profileId, method: "connect", params: modernParams)
            persistDeviceTokenIfPresent(in: result, ref: authContext.deviceTokenRef)
            return
        } catch {
            guard challengeNonce == nil else { throw error }
            Self.log.warning(
                "Modern connect failed without challenge, trying legacy connect: \(error.localizedDescription, privacy: .public)"
            )
        }

        let legacyParams = buildLegacyConnectParams(profile: profile, authContext: authContext)
        _ = try await sendRequest(profileId: profileId, method: "connect", params: legacyParams)
    }

    private func sendRequest(
        profileId: UUID,
        method: String,
        params: [String: AnyCodable]?
    ) async throws -> [String: Any] {
        guard let box = connections[profileId] else {
            throw GatewayClientError.connectionFailed("Not connected")
        }

        let requestId = UUID().uuidString
        let frame = RequestFrame(id: requestId, method: method, params: params)
        let data = try JSONEncoder().encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayClientError.protocolError("Failed to encode request")
        }

        let response = PendingResponse()
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(35))
            await self?.failPendingRequest(
                profileId: profileId,
                requestId: requestId,
                error: GatewayClientError.timeout
            )
        }
        box.pending[requestId] = PendingRequest(response: response, timeoutTask: timeoutTask)

        do {
            try await box.socket.send(.string(text))
        } catch {
            let pending = box.pending.removeValue(forKey: requestId)
            pending?.timeoutTask.cancel()
            response.fail(error)
        }

        let jsonBox = try await response.wait()
        return jsonBox.value
    }

    private func receiveLoop(profileId: UUID) async {
        guard let box = connections[profileId] else { return }

        while !Task.isCancelled {
            do {
                let message = try await box.socket.receive()
                await handleMessage(message, profileId: profileId)
            } catch {
                Self.log.warning(
                    "WebSocket receive error profile=\(box.profileName, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                box.eventContinuation.yield(
                    GatewayEventEnvelope(
                        source: box.profileName,
                        eventType: "connection_error",
                        payload: ["error": error.localizedDescription]
                    )
                )
                break
            }
        }

        box.challengeWaiter.resolve(nil)
        box.eventContinuation.finish()
        box.socket.cancel(with: .normalClosure, reason: nil)
        failPendingRequests(in: box, error: GatewayClientError.connectionFailed("Connection closed"))
        connections.removeValue(forKey: profileId)
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, profileId: UUID) async {
        guard let box = connections[profileId] else { return }

        let jsonText: String
        switch message {
        case let .string(text):
            jsonText = text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else { return }
            jsonText = text
        @unknown default:
            return
        }

        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch object["type"] as? String {
        case "res":
            handleResponse(object, box: box)
        case "event":
            handleEvent(object, box: box)
        default:
            if object["event"] != nil || object["eventType"] != nil || object["taskId"] != nil {
                handleEvent(object, box: box)
            } else {
                Self.log.debug("Unknown frame type: \(object["type"] as? String ?? "nil", privacy: .public)")
            }
        }
    }

    private func handleResponse(_ object: [String: Any], box: ConnectionBox) {
        guard let id = object["id"] as? String,
              let pending = box.pending.removeValue(forKey: id) else {
            return
        }

        pending.timeoutTask.cancel()

        if object["ok"] as? Bool ?? false {
            let payload = object["payload"] as? [String: Any] ?? [:]
            pending.response.succeed(JSONBox(payload))
            return
        }

        let errorObject = object["error"]
        let message: String
        let code: String?
        if let dict = errorObject as? [String: Any] {
            message = dict["message"] as? String ?? "Request failed"
            code = dict["code"] as? String
        } else if let string = errorObject as? String {
            message = string
            code = nil
        } else {
            message = "Request failed"
            code = nil
        }

        if code == "UNAUTHORIZED" || code == "AUTH_FAILED" {
            pending.response.fail(GatewayClientError.unauthorized)
        } else {
            pending.response.fail(GatewayClientError.protocolError(message))
        }
    }

    private func handleEvent(_ object: [String: Any], box: ConnectionBox) {
        let eventName = (object["event"] as? String)
            ?? (object["eventType"] as? String)
            ?? "message"
        let payload = normalizePayload(object["payload"] ?? object)

        if eventName == "connect.challenge" {
            box.challengeWaiter.resolve(payload["nonce"])
            return
        }

        let runId = payload["runId"] ?? payload["run_id"] ?? payload["runid"]
        let sessionId = payload["sessionKey"] ?? payload["session_key"] ?? payload["sessionId"] ?? payload["session_id"]
        let taskId = payload["taskId"] ?? payload["task_id"] ?? payload["clientTaskId"] ?? payload["client_task_id"] ?? runId
        let eventId = payload["eventId"] ?? payload["event_id"] ?? payload["id"] ?? UUID().uuidString

        Self.log.debug(
            "Gateway event profile=\(box.profileName, privacy: .public) type=\(eventName, privacy: .public) runId=\(runId ?? "none", privacy: .public) sessionId=\(sessionId ?? "none", privacy: .public) taskId=\(taskId ?? "none", privacy: .public)"
        )

        let envelope = GatewayEventEnvelope(
            id: eventId,
            source: box.profileName,
            sessionId: sessionId,
            runId: runId,
            taskId: taskId,
            eventType: eventName,
            payload: payload,
            receivedAt: Date()
        )

        box.eventContinuation.yield(envelope)
    }

    private func httpRequest(
        profile: ProfileConfig,
        method: String,
        paths: [String],
        body: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error = GatewayClientError.invalidURL

        for path in paths {
            do {
                guard let url = buildURL(base: profile.gatewayURL, path: path) else {
                    continue
                }

                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = body
                if body != nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                addHTTPAuth(to: &request, profile: profile)

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

    private func addHTTPAuth(to request: inout URLRequest, profile: ProfileConfig) {
        guard let credential = resolvedSharedCredential(for: profile) else {
            return
        }

        request.setValue("Bearer \(credential.value)", forHTTPHeaderField: "Authorization")
    }

    private func authContext(for profile: ProfileConfig) -> ConnectAuthContext {
        let deviceTokenRef = deviceTokenRef(for: profile)
        let storedDeviceToken = (try? secretStore.secret(for: deviceTokenRef))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedCredential = resolvedSharedCredential(for: profile)

        if let storedDeviceToken, !storedDeviceToken.isEmpty {
            return ConnectAuthContext(
                params: [
                    "token": AnyCodable(storedDeviceToken),
                    "deviceToken": AnyCodable(storedDeviceToken),
                ],
                tokenForSignature: storedDeviceToken,
                deviceTokenRef: deviceTokenRef
            )
        }

        if let sharedCredential {
            switch sharedCredential.mode {
            case .token:
                return ConnectAuthContext(
                    params: ["token": AnyCodable(sharedCredential.value)],
                    tokenForSignature: sharedCredential.value,
                    deviceTokenRef: deviceTokenRef
                )
            case .password:
                return ConnectAuthContext(
                    params: ["password": AnyCodable(sharedCredential.value)],
                    tokenForSignature: "",
                    deviceTokenRef: deviceTokenRef
                )
            }
        }

        return ConnectAuthContext(params: nil, tokenForSignature: "", deviceTokenRef: deviceTokenRef)
    }

    private func resolvedSharedCredential(for profile: ProfileConfig) -> GatewayCredential? {
        let environment = ProcessInfo.processInfo.environment
        if let envToken = environment["OPENCLAW_GATEWAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            return GatewayCredential(mode: .token, value: envToken)
        }
        if let envPassword = environment["OPENCLAW_GATEWAY_PASSWORD"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPassword.isEmpty {
            return GatewayCredential(mode: .password, value: envPassword)
        }

        if let launchAgentCredential = Self.loadLaunchAgentCredential() {
            return launchAgentCredential
        }

        return Self.loadLocalGatewayCredential(environment: environment)
    }

    private func buildModernConnectParams(
        profile: ProfileConfig,
        authContext: ConnectAuthContext,
        nonce: String?
    ) throws -> [String: AnyCodable] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let scopes = ["operator.admin", "operator.read", "operator.write", "operator.approvals", "operator.pairing"]
        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let clientId = "openclaw-macos"
        let clientMode = "ui"
        let platform = Self.macOSPlatformString()
        let deviceFamily = "Mac"
        let displayName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "AICP"
        let locale = Locale.preferredLanguages.first ?? Locale.current.identifier

        var params: [String: AnyCodable] = [
            "minProtocol": AnyCodable(3),
            "maxProtocol": AnyCodable(3),
            "client": AnyCodable([
                "id": AnyCodable(clientId),
                "displayName": AnyCodable(displayName.isEmpty ? "AICP" : displayName),
                "version": AnyCodable(version),
                "platform": AnyCodable(platform),
                "deviceFamily": AnyCodable(deviceFamily),
                "mode": AnyCodable(clientMode),
                "instanceId": AnyCodable(clientInstanceId),
            ]),
            "role": AnyCodable("operator"),
            "scopes": AnyCodable(scopes.map(AnyCodable.init)),
            "caps": AnyCodable([AnyCodable]()),
            "commands": AnyCodable([AnyCodable]()),
            "permissions": AnyCodable([String: AnyCodable]()),
            "locale": AnyCodable(locale),
            "userAgent": AnyCodable(ProcessInfo.processInfo.operatingSystemVersionString),
        ]

        if let auth = authContext.params {
            params["auth"] = AnyCodable(auth)
        }

        if let nonce {
            let signaturePayload = Self.buildDeviceAuthSignaturePayload(
                deviceId: deviceIdentity.id,
                clientId: clientId,
                clientMode: clientMode,
                role: "operator",
                scopes: scopes,
                signedAtMs: signedAtMs,
                token: authContext.tokenForSignature,
                nonce: nonce,
                platform: platform,
                deviceFamily: deviceFamily
            )
            let signature = try deviceIdentity.privateKey.signature(for: Data(signaturePayload.utf8))
            params["device"] = AnyCodable([
                "id": AnyCodable(deviceIdentity.id),
                "publicKey": AnyCodable(deviceIdentity.publicKey),
                "signature": AnyCodable(Data(signature).base64URLEncodedString()),
                "signedAt": AnyCodable(signedAtMs),
                "nonce": AnyCodable(nonce),
            ])
        }

        return params
    }

    private func buildLegacyConnectParams(
        profile: ProfileConfig,
        authContext: ConnectAuthContext
    ) -> [String: AnyCodable] {
        var params: [String: AnyCodable] = [
            "role": AnyCodable("operator"),
            "scopes": AnyCodable(["operator.read", "operator.write", "operator.approvals"].map(AnyCodable.init)),
            "client": AnyCodable([
                "name": AnyCodable("AICP"),
                "version": AnyCodable(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"),
                "platform": AnyCodable("macOS"),
            ]),
            "device": AnyCodable([
                "id": AnyCodable(deviceIdentity.id),
            ]),
            "minProtocol": AnyCodable(3),
            "maxProtocol": AnyCodable(3),
        ]

        if let auth = authContext.params {
            params["auth"] = AnyCodable(auth)
        }

        params["local"] = AnyCodable(true)

        return params
    }

    private func persistDeviceTokenIfPresent(in result: [String: Any], ref: String) {
        if let token = stringValue(for: ["auth.deviceToken", "deviceToken"], in: result), !token.isEmpty {
            try? secretStore.setSecret(token, for: ref)
        }
    }

    private func waitForChallenge(profileId: UUID, timeout: TimeInterval) async -> String? {
        guard let box = connections[profileId] else { return nil }
        return await box.challengeWaiter.wait(timeout: timeout)
    }

    private func failPendingRequest(profileId: UUID, requestId: String, error: Error) {
        guard let box = connections[profileId],
              let pending = box.pending.removeValue(forKey: requestId) else {
            return
        }

        pending.timeoutTask.cancel()
        pending.response.fail(error)
    }

    private func failPendingRequests(in box: ConnectionBox, error: Error) {
        for (_, pending) in box.pending {
            pending.timeoutTask.cancel()
            pending.response.fail(error)
        }
        box.pending.removeAll()
    }

    private nonisolated func buildAgentParams(
        draft: TaskDraft,
        agentId: String,
        sessionKey: String
    ) -> [String: AnyCodable] {
        [
            "agentId": AnyCodable(agentId),
            "sessionKey": AnyCodable(sessionKey),
            "message": AnyCodable(draft.prompt),
            "thinking": AnyCodable("low"),
            "deliver": AnyCodable(false),
            "idempotencyKey": AnyCodable(draft.clientTaskId),
        ]
    }

    private nonisolated func parseRoutes(from result: [String: Any]) -> [RouteInfo] {
        if let agents = extractDictionaryArray(keys: ["agents", "items"], from: result), !agents.isEmpty {
            var routes: [RouteInfo] = []
            routes.reserveCapacity(agents.count)
            for item in agents {
                let identity = item["identity"] as? [String: Any]
                let name = stringValue(for: ["name"], in: item)
                    ?? stringValue(for: ["name"], in: identity as Any)
                    ?? stringValue(for: ["id"], in: item)
                    ?? "main"
                routes.append(RouteInfo(
                    id: stringValue(for: ["id"], in: item) ?? "main",
                    displayName: name,
                    metadata: [
                        "identityName": stringValue(for: ["name"], in: identity as Any) ?? "",
                        "identityEmoji": stringValue(for: ["emoji"], in: identity as Any) ?? "",
                    ].filter { !$0.value.isEmpty }
                ))
            }
            return routes
        }

        if let routes = extractDictionaryArray(keys: ["routes"], from: result), !routes.isEmpty {
            var parsed: [RouteInfo] = []
            parsed.reserveCapacity(routes.count)
            for item in routes {
                parsed.append(RouteInfo(
                    id: stringValue(for: ["id", "name"], in: item) ?? "default",
                    displayName: stringValue(for: ["displayName", "label", "name", "id"], in: item) ?? "Default",
                    metadata: (item["metadata"] as? [String: String]) ?? [:]
                ))
            }
            return parsed
        }

        return [RouteInfo(id: "default", displayName: "Default", metadata: [:])]
    }

    private nonisolated func parseRoutesFromJSON(_ data: Data) -> [RouteInfo] {
        if let direct = try? JSONDecoder().decode([RouteInfo].self, from: data), !direct.isEmpty {
            return direct
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let dict = object as? [String: Any] {
                return parseRoutes(from: dict)
            }
            if let items = object as? [[String: Any]], !items.isEmpty {
                return parseRoutes(from: ["agents": items])
            }
        }

        if let wrapped = try? JSONDecoder().decode(RouteEnvelope.self, from: data), !wrapped.routes.isEmpty {
            return wrapped.routes
        }

        return [RouteInfo(id: "default", displayName: "Default", metadata: [:])]
    }

    private nonisolated func parseSentTaskInfo(
        from result: [String: Any],
        fallbackId: String,
        defaultSessionId: String
    ) -> SentTaskInfo {
        let runId = stringValue(for: ["runId", "run_id", "id"], in: result)
        let taskId = stringValue(for: ["taskId", "task_id", "id", "runId", "run_id"], in: result) ?? fallbackId
        let sessionId = stringValue(for: ["sessionKey", "session_key", "sessionId", "session_id"], in: result)
            ?? defaultSessionId
        let statusRaw = stringValue(for: ["status", "state"], in: result)
        return SentTaskInfo(
            taskId: taskId,
            sessionId: sessionId,
            runId: runId ?? taskId,
            status: statusRaw.flatMap(TaskStatus.fromGateway) ?? .queued
        )
    }

    private nonisolated func parseSentTaskInfoFromJSON(
        _ data: Data,
        fallbackId: String,
        defaultSessionId: String
    ) -> SentTaskInfo {
        if let decoded = try? JSONDecoder().decode(SendTaskResponse.self, from: data) {
            let runId = decoded.runId ?? decoded.id ?? decoded.taskId
            return SentTaskInfo(
                taskId: decoded.taskId ?? decoded.id ?? runId ?? fallbackId,
                sessionId: decoded.sessionId ?? decoded.sessionKey ?? defaultSessionId,
                runId: runId ?? fallbackId,
                status: decoded.status.flatMap(TaskStatus.fromGateway) ?? .queued
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parseSentTaskInfo(from: object, fallbackId: fallbackId, defaultSessionId: defaultSessionId)
        }

        return SentTaskInfo(
            taskId: fallbackId,
            sessionId: defaultSessionId,
            runId: fallbackId,
            status: .queued
        )
    }

    private nonisolated func buildURL(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/\(suffix)" : "/\(basePath)/\(suffix)"
        return components.url
    }

    private nonisolated func websocketURL(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        default: components.scheme = "ws"
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components.path = suffix.isEmpty ? "/" : "/\(suffix)"
        } else {
            components.path = suffix.isEmpty ? "/\(basePath)" : "/\(basePath)/\(suffix)"
        }
        return components.url
    }

    private nonisolated func normalizePayload(_ raw: Any) -> [String: String] {
        var normalized: [String: String] = [:]
        flatten(raw, prefix: nil, into: &normalized)
        normalized.removeValue(forKey: "type")
        normalized.removeValue(forKey: "event")
        return normalized
    }

    private nonisolated func flatten(_ raw: Any, prefix: String?, into output: inout [String: String]) {
        if let dict = raw as? [String: Any] {
            for (key, value) in dict {
                let nextPrefix = prefix.map { "\($0).\(key)" } ?? key
                flatten(value, prefix: nextPrefix, into: &output)
            }
            return
        }

        if let dict = raw as? [String: String] {
            for (key, value) in dict {
                let nextPrefix = prefix.map { "\($0).\(key)" } ?? key
                output[nextPrefix] = value
                if output[key] == nil {
                    output[key] = value
                }
            }
            return
        }

        guard let prefix else { return }
        let rendered: String
        if let array = raw as? [Any] {
            rendered = array.map { String(describing: $0) }.joined(separator: ", ")
        } else {
            rendered = String(describing: raw)
        }

        guard rendered != "<null>" else { return }
        output[prefix] = rendered
        if let last = prefix.split(separator: ".").last.map(String.init), output[last] == nil {
            output[last] = rendered
        }
    }

    private nonisolated func extractDictionaryArray(keys: [String], from dict: [String: Any]) -> [[String: Any]]? {
        for key in keys {
            if let value = nestedValue(for: key, in: dict) as? [[String: Any]] {
                return value
            }
        }
        return nil
    }

    private nonisolated func stringValue(for keys: [String], in dict: Any) -> String? {
        guard let object = dict as? [String: Any] else { return nil }
        for key in keys {
            if let value = nestedValue(for: key, in: object) {
                let rendered = String(describing: value)
                if rendered != "<null>" && !rendered.isEmpty {
                    return rendered
                }
            }
        }
        return nil
    }

    private nonisolated func nestedValue(for key: String, in object: [String: Any]) -> Any? {
        key.split(separator: ".").reduce(object as Any?) { partial, segment in
            guard let dict = partial as? [String: Any] else { return nil }
            return dict[String(segment)]
        }
    }

    private nonisolated func normalizedAgentId(from routeId: String) -> String {
        let trimmed = routeId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "default" ? "main" : trimmed
    }

    private nonisolated func sessionKey(for agentId: String) -> String {
        "agent:\(agentId):main"
    }

    private func deviceTokenRef(for profile: ProfileConfig) -> String {
        return "gateway.device.\(profile.id.uuidString)"
    }

    private static func loadOrCreateDeviceIdentity(secretStore: SecretStoring) -> DeviceIdentity {
        let keyRef = "device.identity.privateKey"
        if let stored = try? secretStore.secret(for: keyRef),
           let data = Data(base64EncodedOrURLSafe: stored),
           let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return buildDeviceIdentity(from: privateKey, secretStore: secretStore)
        }

        let privateKey = Curve25519.Signing.PrivateKey()
        try? secretStore.setSecret(privateKey.rawRepresentation.base64EncodedString(), for: keyRef)
        return buildDeviceIdentity(from: privateKey, secretStore: secretStore)
    }

    private static func buildDeviceIdentity(
        from privateKey: Curve25519.Signing.PrivateKey,
        secretStore: SecretStoring
    ) -> DeviceIdentity {
        let publicKeyData = privateKey.publicKey.rawRepresentation
        let id = SHA256.hash(data: publicKeyData).hexString
        let publicKey = publicKeyData.base64URLEncodedString()
        try? secretStore.setSecret(id, for: "device.identity.id")
        try? secretStore.setSecret(publicKey, for: "device.identity.publicKey")
        return DeviceIdentity(
            privateKey: privateKey,
            publicKeyData: publicKeyData,
            publicKey: publicKey,
            id: id
        )
    }

    nonisolated static func buildDeviceAuthSignaturePayload(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String?,
        nonce: String,
        platform: String?,
        deviceFamily: String?
    ) -> String {
        [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token ?? "",
            nonce,
            normalizeMetadataField(platform),
            normalizeMetadataField(deviceFamily),
        ].joined(separator: "|")
    }

    nonisolated static func normalizeMetadataField(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var output = String()
        output.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            let codePoint = scalar.value
            if codePoint >= 65, codePoint <= 90, let lowered = UnicodeScalar(codePoint + 32) {
                output.unicodeScalars.append(lowered)
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private static func loadOrCreateClientInstanceId(secretStore: SecretStoring) -> String {
        let keyRef = "gateway.client.instanceId"
        if let existing = (try? secretStore.secret(for: keyRef))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }

        let instanceId = UUID().uuidString.lowercased()
        try? secretStore.setSecret(instanceId, for: keyRef)
        return instanceId
    }

    private nonisolated static func loadLocalGatewayCredential(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> GatewayCredential? {
        for path in localGatewayConfigPaths() {
            guard let data = try? Data(contentsOf: path) else { continue }
            guard let parsed = parseLocalGatewayCredential(fromConfigData: data, environment: environment) else { continue }
            let mode: GatewayCredentialMode = parsed.mode == "password" ? .password : .token
            return GatewayCredential(mode: mode, value: parsed.credential)
        }
        return nil
    }

    nonisolated static func parseLocalGatewayCredential(
        fromConfigData data: Data,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (mode: String, credential: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let secrets = root["secrets"] as? [String: Any]
        let secretDefaults = secrets?["defaults"] as? [String: Any]
        let secretProviders = secrets?["providers"] as? [String: Any]
        let defaultEnvProvider = (secretDefaults?["env"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultFileProvider = (secretDefaults?["file"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let gateway = root["gateway"] as? [String: Any]
        let auth = gateway?["auth"] as? [String: Any]
        let mode = (auth?["mode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let token = resolveSecretInputString(
            auth?["token"],
            defaultEnvProvider: defaultEnvProvider,
            defaultFileProvider: defaultFileProvider,
            secretProviders: secretProviders,
            environment: environment
        )
        let password = resolveSecretInputString(
            auth?["password"],
            defaultEnvProvider: defaultEnvProvider,
            defaultFileProvider: defaultFileProvider,
            secretProviders: secretProviders,
            environment: environment
        )
        let legacyToken = resolveSecretInputString(
            gateway?["token"],
            defaultEnvProvider: defaultEnvProvider,
            defaultFileProvider: defaultFileProvider,
            secretProviders: secretProviders,
            environment: environment
        )

        if mode == "password", let password, !password.isEmpty {
            return ("password", password)
        }
        if mode == "token", let token, !token.isEmpty {
            return ("token", token)
        }
        if mode == "none" || mode == "trusted-proxy" {
            return nil
        }

        if mode == nil || mode?.isEmpty == true {
            if let token, !token.isEmpty {
                return ("token", token)
            }
            if let password, !password.isEmpty {
                return ("password", password)
            }
        }

        if let legacyToken, !legacyToken.isEmpty {
            return ("token", legacyToken)
        }

        return nil
    }

    private nonisolated static func resolveSecretInputString(
        _ value: Any?,
        defaultEnvProvider: String?,
        defaultFileProvider: String?,
        secretProviders: [String: Any]?,
        environment: [String: String]
    ) -> String? {
        if let direct = trimmedNonEmptyString(value as? String) {
            if let envVar = envTemplateVariable(from: direct) {
                return trimmedNonEmptyString(environment[envVar])
            }
            return direct
        }

        guard let ref = value as? [String: Any] else { return nil }
        let source = (ref["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let provider = (ref["provider"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let id = trimmedNonEmptyString(ref["id"] as? String) else { return nil }

        let matchesDefaultEnvProvider = source == nil
            && provider != nil
            && provider == defaultEnvProvider?.lowercased()

        if source == "env" || matchesDefaultEnvProvider {
            return trimmedNonEmptyString(environment[id])
        }

        let matchesDefaultFileProvider = source == nil
            && provider != nil
            && provider == defaultFileProvider?.lowercased()
        if source == "file" || matchesDefaultFileProvider {
            return resolveFileSecretInputString(
                id: id,
                provider: provider,
                defaultFileProvider: defaultFileProvider,
                secretProviders: secretProviders
            )
        }

        return nil
    }

    private nonisolated static func resolveFileSecretInputString(
        id: String,
        provider: String?,
        defaultFileProvider: String?,
        secretProviders: [String: Any]?
    ) -> String? {
        let providerAlias = provider ?? defaultFileProvider?.lowercased()
        guard let providerAlias,
              let providerConfig = secretProviders?[providerAlias] as? [String: Any] else {
            return nil
        }
        let source = (providerConfig["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard source == "file" else { return nil }
        guard let path = trimmedNonEmptyString(providerConfig["path"] as? String) else { return nil }
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: expandedPath)) else { return nil }

        let explicitMode = (providerConfig["mode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mode = explicitMode ?? (id == "value" ? "singlevalue" : "json")
        if mode == "singlevalue" {
            return trimmedNonEmptyString(String(data: data, encoding: .utf8))
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if id == "value" {
            return renderedSecretValue(root)
        }
        guard let pointerValue = jsonPointerValue(id, in: root) else { return nil }
        return renderedSecretValue(pointerValue)
    }

    private nonisolated static func jsonPointerValue(_ pointer: String, in root: Any) -> Any? {
        guard pointer.hasPrefix("/") else { return nil }
        let segments = pointer
            .split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()
            .map { segment in
                String(segment)
                    .replacingOccurrences(of: "~1", with: "/")
                    .replacingOccurrences(of: "~0", with: "~")
            }

        var current: Any = root
        for segment in segments {
            if let dict = current as? [String: Any] {
                guard let next = dict[segment] else { return nil }
                current = next
                continue
            }
            if let list = current as? [Any],
               let index = Int(segment),
               list.indices.contains(index) {
                current = list[index]
                continue
            }
            return nil
        }
        return current
    }

    private nonisolated static func renderedSecretValue(_ raw: Any) -> String? {
        if raw is [String: Any] || raw is [Any] || raw is NSNull {
            return nil
        }
        return trimmedNonEmptyString(String(describing: raw))
    }

    private nonisolated static func envTemplateVariable(from value: String) -> String? {
        guard value.hasPrefix("${"), value.hasSuffix("}"), value.count > 3 else {
            return nil
        }
        return String(value.dropFirst(2).dropLast())
    }

    private nonisolated static func trimmedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func loadLaunchAgentCredential() -> GatewayCredential? {
        for path in localGatewayLaunchAgentPaths() {
            guard let data = try? Data(contentsOf: path) else { continue }
            guard let parsed = parseLaunchAgentCredential(fromPlistData: data) else { continue }
            let mode: GatewayCredentialMode = parsed.mode == "password" ? .password : .token
            return GatewayCredential(mode: mode, value: parsed.credential)
        }
        return nil
    }

    nonisolated static func parseLaunchAgentCredential(fromPlistData data: Data) -> (mode: String, credential: String)? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        if let env = root["EnvironmentVariables"] as? [String: Any] {
            if let token = trimmedNonEmptyString(env["OPENCLAW_GATEWAY_TOKEN"] as? String) {
                return ("token", token)
            }
            if let password = trimmedNonEmptyString(env["OPENCLAW_GATEWAY_PASSWORD"] as? String) {
                return ("password", password)
            }
        }

        if let args = root["ProgramArguments"] as? [String] {
            if let token = commandFlagValue("--token", args: args) {
                return ("token", token)
            }
            if let password = commandFlagValue("--password", args: args) {
                return ("password", password)
            }
        }

        return nil
    }

    private nonisolated static func commandFlagValue(_ flag: String, args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else {
            return nil
        }
        return trimmedNonEmptyString(args[index + 1])
    }

    private nonisolated static func localGatewayConfigPaths() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configPath = environment["OPENCLAW_CONFIG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configPath.isEmpty {
            candidates.append((configPath as NSString).expandingTildeInPath)
        }
        if let stateDir = environment["OPENCLAW_STATE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stateDir.isEmpty {
            let expanded = (stateDir as NSString).expandingTildeInPath
            candidates.append((expanded as NSString).appendingPathComponent("openclaw.json"))
        }

        let defaultConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw")
            .appendingPathComponent("openclaw.json")
            .path
        candidates.append(defaultConfig)

        var unique: [URL] = []
        var seen: Set<String> = []
        for path in candidates {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(normalizedPath).inserted {
                unique.append(URL(fileURLWithPath: normalizedPath))
            }
        }
        return unique
    }

    private nonisolated static func localGatewayLaunchAgentPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Library/LaunchAgents/ai.openclaw.gateway.plist",
            "/Library/LaunchAgents/ai.openclaw.gateway.plist",
        ]

        var unique: [URL] = []
        var seen: Set<String> = []
        for path in candidates {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(normalizedPath).inserted {
                unique.append(URL(fileURLWithPath: normalizedPath))
            }
        }
        return unique
    }

    private nonisolated static func macOSPlatformString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

private struct RouteEnvelope: Decodable {
    var routes: [RouteInfo]
}

private struct SendTaskResponse: Decodable {
    var id: String?
    var taskId: String?
    var sessionId: String?
    var sessionKey: String?
    var runId: String?
    var status: String?
}

extension TaskStatus {
    static func fromGateway(_ raw: String) -> TaskStatus? {
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        switch normalized {
        case "draft": return .draft
        case "queued", "pending", "accepted": return .queued
        case "running", "in_progress", "delta", "start": return .running
        case "needs_input", "question", "approval_requested": return .needsInput
        case "completed", "done", "success", "ok", "final", "end": return .completed
        case "failed", "error": return .failed
        case "canceled", "cancelled", "aborted", "timeout": return .canceled
        case "needs_attention": return .needsAttention
        default: return nil
        }
    }
}

private extension Data {
    init?(base64EncodedOrURLSafe string: String) {
        let padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        let normalized = remainder == 0 ? padded : padded + String(repeating: "=", count: 4 - remainder)
        self.init(base64Encoded: normalized)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension SHA256Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
