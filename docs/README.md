# AICP - AI Control Plane Docs

This folder contains the product and engineering source of truth for the AICP - AI Control Plane.

## Document Map

- [Vision](./vision.md)
A concise statement of the problem, product goals, audience, and non-goals.

- [User Experience](./user-experience.md)
Interaction model, UI surfaces, primary flows, and UX constraints.

- [Technical Plan](./technical-plan.md)
Architecture, module responsibilities, data model contracts, operational model, and testing strategy.

- [Current Implementation Status](./current-status.md)
What is already implemented in this repository right now.

- [Remaining Work and Roadmap](./remaining-work.md)
What still needs to be built, ordered into practical milestones.

## Quick Summary

- Platform: native macOS notch-style companion (`SwiftUI + AppKit`).
- Control plane: OpenClaw-first orchestration.
- Scope: single-user power users who already have OpenClaw.
- Core loop: send prompt, monitor run, answer follow-up, manually chain next task.
