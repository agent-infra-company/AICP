---
name: notch-app-builder
description: Design, build, or explain macOS notch-style apps that render interactive UI at the top-center of the display using SwiftUI/AppKit windows. Use when implementing notch open/close behavior, hover and gesture interactions, multi-display positioning, media controls, drag-and-drop shelves, HUD replacement, permissions, XPC helpers, or release pipelines for a notch app.
---

# Notch App Builder

## Overview
Build notch apps as a layered system: a floating window layer, a notch state/view model layer, feature modules, privileged helper integration, and a release pipeline.
Use this workflow to create new notch apps or to extend an existing one without breaking window behavior or permissions.

## Workflow

## 1. Define the Notch Contract
Define the contract before writing UI:
- Anchor notch UI to top-center of a screen.
- Support two core states: `closed` and `open`.
- Keep a deterministic trigger model: hover, click, gesture, keyboard shortcut, or drag-enter.
- Handle multi-display explicitly: single selected display or all displays.
- Decide whether UI should appear on lock screen and in screen recordings.

Capture these as concrete state variables early (`notchState`, `screenUUID`, display mode flags).

## 2. Build the Windowing Layer First
Implement an AppKit window layer before feature work:
- Create a borderless/non-activating top-level panel.
- Set level above menu bar (`.mainMenu + n`) and join all spaces if needed.
- Reposition on screen changes and display preference changes.
- Keep per-screen windows and per-screen view models when supporting all displays.

Do not start with media or animations until this is stable.

## 3. Implement a Single Source of Truth for Notch State
Centralize state in one model:
- `open()` must set notch size/state and trigger data refreshes.
- `close()` must reset transient UI state and refuse closure during critical operations (for example, active sharing sheets).
- Derive effective notch height for non-notch displays and fullscreen edge cases.
- Publish drop-target, hover, and popover state with predictable transitions.

Keep state transitions small and explicit to avoid UI race conditions.

## 4. Add Interaction and Motion
Add interactions incrementally:
- Hover open/close with cancellable delayed tasks.
- Click-to-open fallback.
- Optional pan gestures for open/close.
- Drag-enter expansion path for drop surfaces.
- Context menu and keyboard shortcut hooks.

Prefer predictable spring timings over heavy chained animations.

## 5. Integrate Features as Isolated Modules
Add modules behind managers/controllers, not in root view:
- Media playback controller abstraction (Apple Music / Spotify / NowPlaying / external connector).
- Calendar/reminders provider.
- Camera/mirror manager.
- Shelf/drop/persistence services.
- HUD indicators (volume/brightness/backlight).

Define protocol-based interfaces where app integrations differ per provider.

## 6. Handle Privileged Operations via XPC Helper
When direct access is sensitive or unstable:
- Move accessibility checks/prompts to an XPC helper.
- Move private framework access (for example screen/keyboard brightness) to helper boundaries.
- Keep main app on async client calls and observe authorization changes.
- Make helper failure non-fatal and degrade gracefully.

Treat helper APIs as capability checks (`isAvailable`, `current`, `set`) with clear fallbacks.

## 7. Wire Settings and Persistence
Expose settings for behavior, appearance, and feature toggles:
- Persist lightweight preferences (`Defaults`/`AppStorage`).
- Post notifications for settings that require window/layout recompute.
- Keep advanced options behind explicit toggles (HUD replacement, lock-screen rendering, screen-recording visibility).

Separate settings window lifecycle from notch windows.

## 8. Build, Sign, Package, and Update
Use CI with reproducible macOS builds:
- Resolve Swift packages.
- Build/archive with explicit Xcode version.
- Export `.app`, package `.dmg`, and publish artifacts.
- Generate and publish Sparkle appcast for updates.

Keep release logic scriptable and avoid manual version edits.

## 9. Verify Before Shipping
Run a focused checklist:
- Window anchoring works across display changes.
- Open/close does not flicker under rapid hover and drag.
- Fullscreen and lock-screen behavior matches settings.
- Helper prompts and failures are handled safely.
- Media controls fail gracefully when provider app is absent.
- Drop/persistence survives app restarts.
- Update feed and package artifacts are valid.

## Reference File
Read [references/boring-notch-implementation.md](./references/boring-notch-implementation.md) when implementing against this repository.
Use it to map each architecture step to concrete files in `boring.notch`.
