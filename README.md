# AICP - AI Control Plane

A macOS notch companion for AI task coordination.

<!-- ![Screenshot](docs/assets/screenshot.png) -->

AICP lives near your MacBook's notch and acts as a lightweight command center for AI workflows. Send prompts, monitor running tasks, respond to follow-up questions, and track history — all without leaving your current context.

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

> Distribution builds coming soon. See [Building from Source](#building-from-source) below.

### Building from Source

```bash
# Clone the repository
git clone <repo-url>
cd clawy

# Build
swift build

# Run (development mode)
swift run
```

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

## Architecture

The app follows a layered architecture:

```
UI (SwiftUI)  →  Core (CompanionCore + TaskStateMachine)  →  Services  →  Models
                                                              ├── OpenClawGatewayClient
                                                              ├── DefaultRuntimeManager
                                                              ├── EncryptedPersistenceStore
                                                              ├── TaskSourceAggregator
                                                              ├── NotificationService
                                                              └── TelemetryManager
```

See [`docs/`](docs/) for detailed product vision, UX documentation, technical architecture, and roadmap.

## Contributing

Contributions are welcome. Please open an issue to discuss proposed changes before submitting a pull request:
<https://github.com/apupneja/clawy/issues>

## License

[MIT](./LICENSE)
