# Vision

## Product Vision

Create a fast, reliable top-bar AI companion for macOS that lives near the hardware notch and acts as an operational cockpit for OpenClaw-powered task coordination.

The companion should let a user run their AI workflow without constantly switching windows: send prompts, track runs, answer follow-up questions, and move to the next task.

## Problem Statement

Power users coordinating AI workflows across tools lose time and context by:

- Jumping between terminals, browser tabs, IDE panes, and chat windows.
- Missing follow-up questions that block long-running tasks.
- Having no persistent, lightweight command center for runtime status and interventions.

## Target Audience

Single-user power users on macOS who:

- Already run OpenClaw locally or remotely.
- Need quick operational control over AI runs.
- Want low-friction visibility and response loops.

## Core Product Goals

1. Keep critical workflow controls one click away near the notch.
2. Make `Needs Input` moments impossible to miss.
3. Support both local and remote OpenClaw profiles without changing user mental model.
4. Keep execution safe (no arbitrary shell entry points from UI).
5. Preserve continuity (encrypted local history and state).

## Non-Goals (v1)

- Provisioning OpenClaw for users who do not already have it.
- Multi-user collaboration, roles, or shared workspaces.
- Full DAG workflow orchestration engine.
- File attachment pipeline.
- General-purpose plugin marketplace.

## Product Principles

- Companion-first: minimal context switching.
- Deterministic state transitions over implicit magic.
- Safe operations by default, especially for runtime controls.
- Configuration for power users, not hidden behavior.
- Graceful degradation when integrations fail.
