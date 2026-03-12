# AICP - AI Control Plane

A macOS notch companion for AI task coordination.

<!-- ![Screenshot](docs/assets/screenshot.png) -->

AICP lives near your MacBook's notch and acts as a lightweight command center for AI workflows. Send prompts, monitor running tasks, respond to follow-up questions, and track history — all without leaving your current context.

## Current State & Vision

Today, AICP relies on a number of workarounds to discover, retrieve, and review tasks across different AI coding platforms (Claude Code, Codex CLI, Cursor, etc.). Each platform exposes different interfaces—or none at all—so the integration layer is largely built on heuristics, polling, and screen-scraping rather than clean APIs.

Over time, we'd like to propose **a standard protocol for AI control planes across platforms**. The goal is a shared, open specification that any AI coding tool can implement, enabling a unified surface for task submission, status streaming, follow-up handling, and history—without per-platform workarounds. If you're interested in collaborating on this, open an issue or reach out.

## Features

- **Notch-native UI** — Expands from the macOS notch area with collapsed and expanded layouts
- **OpenClaw integration** — WebSocket event streaming, HTTP task submission, multi-profile support (local and remote)
- **Multi-source task monitoring** — Tracks sessions from Claude Code, Codex CLI, Claude Desktop, Cursor, and web AI chats (ChatGPT, Claude, Gemini)
- **CLI session launcher** — Launch Claude Code and Codex CLI sessions from the companion, with the composed prompt copied to the clipboard for quick pasting
- **Deterministic state machine** — Clear task lifecycle: draft → queued → running → needs input → completed/failed
- **Smart notifications** — macOS notifications for task completion, failure, and follow-up requests with deep-link support
- **Encrypted persistence** — AES-GCM encryption at rest with Keychain-backed key management
- **Runtime lifecycle control** — Start, stop, restart, and check status of OpenClaw runtimes via configurable command templates
- **Privacy-first telemetry** — Optional, opt-in local event logging only

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0+ (for building from source)
- An OpenClaw gateway (local or remote) for task orchestration

## Installation

### Download

Download the latest `.dmg` or `.zip` from [Releases](https://github.com/agent-infra-company/AICP/releases), then drag `AICP.app` to `/Applications`.

### Quick Install

```bash
git clone https://github.com/agent-infra-company/AICP.git
cd AICP
make install
```

This builds a release `.app` bundle and copies it to `/Applications`. Launch from Spotlight or `/Applications/AICP.app`.

### Building from Source

```bash
git clone https://github.com/agent-infra-company/AICP.git
cd AICP

# Build and run the .app bundle
make app
open dist/AICP.app

# Or run in development mode (unbundled, limited features)
swift run
```

#### Build Commands

| Command | Description |
|---------|-------------|
| `make app` | Build release `.app` bundle to `dist/` |
| `make install` | Build and install to `/Applications` |
| `make uninstall` | Remove from `/Applications` |
| `make dmg` | Build and create a `.dmg` for distribution |
| `make zip` | Build and create a `.zip` for distribution |
| `make run` | Run in dev mode (unbundled) |
| `make test` | Run tests |
| `make clean` | Remove build artifacts |

> **Note:** Running via `swift run` launches in unbundled mode. Menu bar integration, notification permissions, and the full onboarding flow require launching the built `.app` bundle.

## Quick Start

1. **Launch** the app — the notch companion appears at the top of your primary display
2. **Configure** a gateway profile during onboarding (default: `http://127.0.0.1:4689`)
3. **Hover** over the notch area to expand the companion
4. **Compose** a prompt and either send it to an OpenClaw route or launch a CLI session with the prompt copied to your clipboard
5. **Monitor** task progress in the Running tab
6. **Respond** to follow-up questions in the Needs Input tab
7. **Review** completed tasks in History

## Settings

Access settings from the menu bar icon. Configuration options include:

- **General** — Launch at login, fullscreen behavior, screen recording visibility, telemetry opt-in, history retention
- **Appearance** — Notch glow style and color
- **Profiles** — Local and remote OpenClaw gateway connections with bearer token or SSH authentication
- **Command Templates** — Customizable runtime lifecycle commands (start, stop, restart, status) with safe placeholder substitution
- **About** — Version info, feedback links, diagnostics export


## Registering a Custom Agent

AICP exposes a standard process for registering, tracking, and messaging any agent. Whether you're running a remote agent behind an HTTP API, a local daemon, or a custom tool — you can plug it into AICP with a few lines of code or by pointing it at a URL.

### Quick start: register a remote agent

If your agent exposes a standard HTTP API (see contract below), register it in one call:

```swift
await core.registerRemoteAgent(
    id: "my-agent",
    displayName: "My Agent",
    endpointURL: URL(string: "http://localhost:9000")!,
    iconSystemName: "cpu",       // SF Symbol name
    iconColorHex: "#FF6600"      // hex color for the icon
)
```

The agent will immediately appear in the CLI picker, and AICP will start tracking its tasks and showing them in the notch UI.

### Agent HTTP API contract

Any agent that speaks this standard HTTP/WebSocket protocol works with AICP out of the box:

| Endpoint | Method | Request Body | Response Body | Purpose |
|---|---|---|---|---|
| `/health` | `GET` | — | `2xx` | Health check / reachability |
| `/routes` | `GET` | — | `[{"id": "...", "displayName": "...", "metadata": {}}]` | Discover capabilities |
| `/tasks` | `POST` | `AgentMessage` (below) | `AgentResponse` (below) | Submit a task/message |
| `/tasks/:id/answer` | `POST` | `{"answer": "..."}` | `2xx` | Answer a follow-up question |
| `/events` | `WebSocket` | — | Stream of event envelope JSON frames | Real-time task updates |

**AgentMessage** (POST `/tasks` body):
```json
{
  "taskId": "uuid",
  "routeId": "default",
  "title": "Fix the login bug",
  "prompt": "The login page throws a 500 when...",
  "metadata": {}
}
```

**AgentResponse** (POST `/tasks` response):
```json
{
  "taskId": "uuid",
  "sessionId": "optional-session-id",
  "runId": "optional-run-id",
  "status": "running",
  "message": "Task accepted"
}
```

**Event envelope** (WebSocket `/events` frames):
```json
{
  "id": "event-uuid",
  "source": "my-agent",
  "taskId": "task-uuid",
  "eventType": "progress",
  "payload": {"progress": "Analyzing code...", "title": "Fix login bug"},
  "receivedAt": "2025-01-01T00:00:00Z"
}
```

Supported `eventType` values: `progress`, `needs_input`, `completed`, `failed`, `canceled`, `queued`.

### Advanced: custom transport or monitor-only agents

For agents that don't speak HTTP, implement the `AgentTransport` protocol directly:

```swift
// 1. Describe the agent
let descriptor = AgentDescriptor(
    id: "my-custom-agent",
    displayName: "My Custom Agent",
    iconSystemName: "cpu",
    iconColorHex: "#FF6600",
    supportsMessaging: true,
    supportsFollowUp: true,
    endpointURL: URL(string: "http://localhost:9000")!
)

// 2. Implement the transport protocol
class MyTransport: AgentTransport {
    let agentId = "my-custom-agent"
    func discoverRoutes() async throws -> [RouteInfo] { ... }
    func sendTask(_ message: AgentMessage) async throws -> AgentResponse { ... }
    func answerFollowUp(taskId: String, answer: String) async throws { ... }
    func subscribeEvents() async -> AsyncStream<GatewayEventEnvelope> { ... }
    func isReachable() async -> Bool { ... }
    func connect() async throws { ... }
    func disconnect() async { ... }
}

// 3. Register
await core.registerAgent(descriptor: descriptor, transport: MyTransport())
```

For **monitor-only agents** (track tasks without sending messages), implement `TaskSource` instead:

```swift
let descriptor = AgentDescriptor(
    id: "my-watcher",
    displayName: "My Watcher",
    supportsMessaging: false
)

class MyMonitor: TaskSource {
    let sourceKind: TaskSourceKind = .custom("my-watcher")
    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> { ... }
    func stopMonitoring() async { ... }
    func isAvailable() async -> Bool { ... }
}

await core.registerAgent(descriptor: descriptor, monitor: MyMonitor())
```

### Unregistering an agent

```swift
await core.unregisterAgent(id: "my-agent")
```

### Prompt for AI assistants

Use this prompt to have an AI coding assistant set up agent registration for any application:

> I want to register a custom agent with AICP (AI Control Plane). The agent is **[DESCRIBE YOUR AGENT — name, what it does, where it runs, its API endpoint if any]**.
>
> Please:
> 1. Create an HTTP server that implements the AICP agent contract:
>    - `GET /health` — return 200
>    - `GET /routes` — return a JSON array of `{"id", "displayName", "metadata"}` objects
>    - `POST /tasks` — accept `{"taskId", "routeId", "title", "prompt", "metadata"}`, start the work, return `{"taskId", "status": "running"}`
>    - `POST /tasks/:id/answer` — accept `{"answer": "..."}` for follow-up questions
>    - `WS /events` — stream JSON event envelopes with `{"id", "source", "taskId", "eventType", "payload", "receivedAt"}` where eventType is one of: `progress`, `needs_input`, `completed`, `failed`, `canceled`, `queued`
> 2. Register it with AICP using `core.registerRemoteAgent(id: "...", displayName: "...", endpointURL: URL(string: "http://...")!)`.
> 3. Show me how to verify it appears in the AICP notch UI and can receive messages.

## Architecture

The app follows a layered architecture:

```
UI (SwiftUI)  →  Core (ControlPlaneCore + TaskStateMachine)  →  Services  →  Models
                                                                 ├── AgentRegistry
                                                                 ├── OpenClawGatewayClient
                                                                 ├── HTTPAgentTransport
                                                                 ├── DefaultRuntimeManager
                                                                 ├── EncryptedPersistenceStore
                                                                 ├── TaskSourceAggregator
                                                                 ├── NotificationService
                                                                 └── TelemetryManager
```

See [`docs/`](docs/) for detailed product vision, UX documentation, technical architecture, and roadmap.

## Contributing

Contributions are welcome. Please open an issue to discuss proposed changes before submitting a pull request:
<https://github.com/agent-infra-company/AICP/issues>

## License

[MIT](./LICENSE)
