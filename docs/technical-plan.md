# Technical Plan

## Architecture Overview

The codebase is organized as a layered macOS app:

1. Windowing and shell
2. UI composition
3. Companion orchestration core (state + flows)
4. Service interfaces and implementations
5. Model contracts
6. Persistence and security

## Modules and Responsibilities

### App bootstrap

- `Sources/ClawdbotNotchCompanion/App/ClawdbotNotchCompanionApp.swift`
- `Sources/ClawdbotNotchCompanion/App/AppDelegate.swift`

Responsibilities:

- Instantiate concrete service implementations.
- Build the `CompanionCore` dependency graph.
- Start the notch shell and notification delegation.

### Windowing

- `Windowing/NotchPanel.swift`
- `Windowing/NotchShellController.swift`

Responsibilities:

- Create borderless top-level panel.
- Anchor to top-center on primary display.
- Track expanded/collapsed frame transitions.
- Detect notch-adjacent click hit zone.
- Apply fullscreen and recording visibility settings.

### Orchestration Core

- `Core/CompanionCore.swift`
- `Core/TaskStateMachine.swift`

Responsibilities:

- Maintain single source of truth for app state.
- Enforce deterministic task state transitions.
- Implement submit/monitor/follow-up/retry workflow.
- Coordinate runtime health checks and gateway connectivity.
- Persist state updates and retention cleanup.

### Gateway Integration

- `Services/GatewayClient.swift`
- `Services/OpenClawGatewayClient.swift`

Responsibilities:

- Connect to OpenClaw WS event stream.
- Discover routes.
- Send tasks and follow-up answers.
- Normalize event payloads into app event envelopes.

Current compatibility behavior:

- HTTP path fallback (`/routes`, `/v1/routes`, `/api/routes`, etc.).
- Flexible JSON parsing for mixed gateway schemas.

### Runtime Control

- `Services/RuntimeManager.swift`
- `Services/DefaultRuntimeManager.swift`
- `Services/CommandTemplateEngine.swift`
- `Services/CommandWhitelistValidator.swift`
- `Services/ShellCommandExecutor.swift`

Responsibilities:

- Execute `start|stop|restart|status` lifecycle actions.
- Render command templates with allowed placeholders.
- Reject unsafe command expansions.
- Support remote execution via SSH template wrapping.

### Persistence and Security

- `Services/PersistenceStore.swift`
- `Services/SecretStore.swift`
- `Services/KeychainSymmetricKeyProvider.swift`

Responsibilities:

- Encrypt persisted app state at rest using AES-GCM.
- Store encryption key material in Keychain.
- Store profile secrets (tokens) in Keychain.

### Notifications, telemetry, operations

- `Services/NotificationService.swift`
- `Services/TelemetryManager.swift`
- `Services/LoginItemManager.swift`
- `Services/RetentionScheduler.swift`

Responsibilities:

- Send notifications for needs input/completion/failure.
- Record opt-in local telemetry events.
- Manage launch-at-login behavior.
- Trigger retention cleanup on schedule.

### Extension point for future bridges

- `Services/BridgeRegistry.swift`

Responsibilities:

- Provide a narrow registry interface for future external tool bridges.

## Data Contracts

Core model contracts implemented under `Models/`:

- `ProfileConfig`
- `CommandTemplateSet`
- `TaskRecord`
- `TaskStatus`
- `GatewayEventEnvelope`
- `RouteInfo`
- `TaskDraft`
- `SentTaskInfo`
- `RuntimeStatus`
- `AppSettings`

These represent the public app-level interfaces for workflow, routing, lifecycle management, and persistence.

## State Machine

Implemented task transition model:

- `draft -> queued -> running`
- `running -> needs_input -> running`
- Terminal states: `completed`, `canceled`, `failed`, `needs_attention`
- Failure policy: auto-retry once; then escalate to `needs_attention`.

## Testing Strategy

Current unit coverage includes:

- Task state transitions and invalid transition guards.
- Command template rendering and injection safety checks.
- Command whitelist validation.
- Encrypted persistence round-trip + plaintext non-leak check.

See `Tests/ClawdbotNotchCompanionTests/` for concrete test cases.

## Build and Run

- Build/test toolchain: Swift Package Manager.
- Command: `swift test`.
- Current test status: passing (9 tests).
