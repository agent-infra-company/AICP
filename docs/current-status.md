# Current Implementation Status

This document captures what is implemented as of March 4, 2026.

## Implemented

### Core app structure

- Greenfield native macOS Swift package app scaffolded.
- App entry and delegate wired.
- Menu bar extra + settings scene available.

### Notch shell and top bar behavior

- Borderless top-level companion panel.
- Collapsed and expanded layouts.
- Notch-adjacent click zone opens panel.
- Click outside panel collapses it.
- Fullscreen and screen recording visibility settings wired to window behavior.

### Companion workflow loop

- `Compose`, `Running`, `Needs Input`, `History` tabs implemented.
- Prompt submission flow implemented.
- Route/profile selection implemented.
- Follow-up response flow implemented.
- Inline error banner support implemented.

### Orchestration and state management

- Single-source `CompanionCore` with published UI state.
- Deterministic `TaskStateMachine`.
- Retry-once then `needs_attention` behavior implemented.
- Runtime health check before prompt submission.

### OpenClaw integration

- WS event subscription path (`/events`) with stream fanout.
- HTTP route discovery with endpoint fallback.
- HTTP task submission with endpoint fallback.
- HTTP follow-up answer with endpoint fallback.
- Flexible response parsing for schema variance.

### Runtime lifecycle control

- Lifecycle actions: start, stop, restart, status.
- Local command template execution.
- Remote command execution via SSH reference + template.
- Template placeholder substitution with safety checks.
- Confirmation workflow for stop/restart in UI.

### Persistence and security

- Encrypted state file at rest (AES-GCM).
- Symmetric key loaded/created via Keychain provider.
- Keychain secret store for auth token references.
- Settings and task history persistence implemented.
- Retention cleanup scheduler implemented.

### Notifications and telemetry

- Local notification preparation + category.
- Notifications for needs input, completion, and failure.
- Notification deep-link behavior into task focus.
- Opt-in local telemetry event logging implemented.

### Testing

- Unit tests for:
  - state transitions,
  - command template safety,
  - whitelist validation,
  - encrypted persistence.
- `swift test` passes.

## Partially Implemented / Basic Version

- Multi-display behavior is currently primary-display oriented, with no advanced display-follow logic.
- Remote profile security model exists (token ref + SSH ref) but does not yet include deeper policy controls like host key pinning or signed command manifests.
- OpenClaw API handling is robust/fallback-based, but not yet pinned to one explicit gateway schema contract version.

## Not Yet Implemented

- Signed app distribution pipeline (signing, notarization, CI release automation).
- Hardened production telemetry pipeline (currently local opt-in logging only).
- Bridge implementations for phase-2 IDE agent integrations (registry only).
- Advanced UX polish and accessibility pass.
- End-to-end integration tests with a live OpenClaw gateway harness.
