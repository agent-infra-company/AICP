# User Experience

## Interaction Model

The app has two states:

- Collapsed chip near the notch: quick status glance (`running`, `needs input`).
- Expanded panel: full operational workspace with task and runtime controls.

Default interaction is click-to-open using an expanded notch-adjacent hit zone.

## Main Surfaces

- Collapsed Companion
  - Shows companion status indicator.
  - Shows running count and needs-input count.

- Expanded Companion Tabs
  - `Compose`: submit task prompt to selected profile/route.
  - `Running`: monitor active queued/running tasks.
  - `Needs Input`: answer follow-up prompts to unblock runs.
  - `History`: review completed/failed/canceled/attention tasks.

- Settings
  - Manage profiles and route behavior.
  - Manage runtime command templates.
  - Configure privacy/visibility/retention/startup preferences.

## Primary User Flow

1. Click near hardware notch.
2. Panel expands.
3. Select profile + route.
4. Submit prompt from `Compose`.
5. Monitor progress in `Running`.
6. If follow-up is requested, task moves to `Needs Input` and macOS notification is sent.
7. Answer question from companion panel.
8. Task resumes and eventually completes/fails.
9. User manually chains the next task.

## Runtime Control UX

Users can perform:

- `Start`
- `Status`
- `Restart`
- `Stop`

Confirmation behavior:

- `Stop` and `Restart` require explicit confirmation.
- `Start` and `Status` are immediate.

## Visibility and Presence

- Primary display oriented behavior.
- Companion can appear in fullscreen when enabled.
- Screen recording visibility can be hidden by default (toggleable).
- Launch-at-login is configurable.

## UX Constraints and Standards

- Sending a prompt should require minimal interaction (target: under 3 clicks after panel open).
- `Needs Input` must be highly visible in both collapsed and expanded states.
- Errors should be surfaced inline without collapsing context.
- Closing/opening the panel should be visually stable and predictable.
