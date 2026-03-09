# Contributing

## Getting Started

```bash
swift build
swift test
```

Run development builds with:

```bash
swift run
```

`swift run` launches the app in unbundled mode, so menu bar integration, onboarding, and notification permissions are limited compared to a bundled `.app`.

## Pull Requests

- Open an issue first for substantial behavior changes.
- Keep pull requests focused and include tests for new logic.
- Update `README.md` or `docs/` when user-visible behavior changes.

## Quality Bar

- `swift test` must pass locally.
- New code should preserve the service boundaries used in `Sources/AICP`.
- Avoid private macOS APIs unless they are explicitly documented and optional.

## Reporting Issues

Use GitHub Issues:
<https://github.com/apupneja/clawy/issues>
