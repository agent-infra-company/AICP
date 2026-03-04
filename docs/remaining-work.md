# Remaining Work and Roadmap

## Objective

Move from a functional development implementation to a production-ready v1 release for power users.

## Milestone 1: Integration Hardening

### Goals

- Lock OpenClaw gateway API contract(s) by version.
- Improve reconnection and event stream resilience.
- Validate local and remote profile behavior under failure conditions.

### Tasks

- Add explicit gateway compatibility matrix and parser profiles.
- Add backoff + jitter reconnect strategy with visibility in UI.
- Add connection diagnostics panel per profile.
- Add integration tests using local mock gateway and fixture event streams.

## Milestone 2: Runtime Safety and Ops Quality

### Goals

- Strengthen remote execution safety.
- Improve operator trust around lifecycle actions.

### Tasks

- Add optional SSH host allowlist and fingerprint verification guidance.
- Add structured audit log for runtime actions.
- Add stricter command template validation policy and linting in settings.
- Add dry-run preview for lifecycle commands before save.

## Milestone 3: UX Refinement and Accessibility

### Goals

- Ensure day-to-day reliability and polish for heavy users.

### Tasks

- Improve notch animations and visual hierarchy under load.
- Add keyboard-first navigation and shortcuts across all tabs.
- Add VoiceOver labels/traits and dynamic type audits.
- Add richer history filtering and search.

## Milestone 4: Release Engineering

### Goals

- Ship as a signed direct macOS app.

### Tasks

- Add Xcode project/workspace alignment if needed for distribution tooling.
- Configure code signing identities and entitlements.
- Implement notarization and staple flow.
- Add CI workflows for build, test, sign, notarize, package.
- Produce release artifacts and changelog process.

## Milestone 5: Phase-2 Bridges (Post-v1)

### Goals

- Extend beyond OpenClaw-first without disrupting core loop.

### Tasks

- Implement first bridge(s) via `BridgeRegistry`.
- Add bridge capability discovery in settings.
- Add bridge routing UI and health indicators.
- Add compatibility tests for bridge-specific task translation.

## Cross-Cutting Backlog

- End-to-end tests: prompt -> run -> needs input -> answer -> complete.
- Stress/perf tests with 20+ concurrent active tasks.
- Crash recovery and state repair UX for corrupted or partial state.
- Security review for keychain usage and persisted data lifecycle.

## Recommended Definition of Done for v1

- Stable OpenClaw contract for at least one gateway version.
- Runtime actions safe by default and auditable.
- All acceptance criteria from product plan validated manually + via tests.
- Signed and notarized app artifact produced in CI.
