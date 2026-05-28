# TUI Gaps for Foundry-hosted Hermes

Current goal: a remote Hermes agent primarily accessed through the local TUI. Other chat
platforms can be added later as separate entrypoints, so this document focuses on TUI
communication and scheduled maintenance wakeups.

## Summary

The core TUI path is already broader than a narrow whitelist. The local Foundry TUI
backend handles a few local/proxy-specific methods, then forwards unknown JSON-RPC
methods through the hosted agent's `hermes.rpc` envelope to the Hermes gateway running
inside the Foundry sandbox.

That means most TUI surfaces should already route to remote Hermes. The remaining gaps
are mostly about durability, local-to-remote file transfer beyond images, Routine payload
shape, and background work semantics in an idle-suspending hosted runtime.

## Should work today

| Area | Status | Notes |
|---|---|---|
| Core TUI RPC tunnel | Works | Unknown methods fall through to the hosted Hermes gateway through `hermes.rpc`, so most TUI JSON-RPC methods should route without explicit proxy code. |
| Session lifecycle | Mostly works | `session.create` and `session.resume` are tracked locally so the proxy can subscribe to events for the returned session. Other session methods such as list, status, history, save, delete, branch, compress, undo, and usage are forwarded. |
| Prompt streaming | Works | `prompt.submit` is a normal RPC that returns `status: streaming`; streamed output arrives separately over `session.events`. |
| Live TUI events | Works while connected | The hosted side emits events into an in-memory per-session buffer. The local proxy subscribes via `session.events` and forwards message, tool, status, approval, clarify, sudo, secret, and other event frames to the TUI. |
| Interrupt and control responses | Mostly works | `session.interrupt` passes through. `clarify.respond`, `approval.respond`, `sudo.respond`, and `secret.respond` remember pending request ownership and inject the right `session_id` when the TUI response does not include one. |
| Slash commands and autocomplete | Works | `commands.catalog` is cached locally for fast top-level slash completion. Sub-command and argument completion falls through to hosted Hermes. The cache invalidates on skill/reload changes and replay gaps. |
| Shell, tools, file edits, `/cd` | Works in the sandbox | These run in the Foundry workspace, not on the laptop. This is expected for a remote-agent setup. |
| Path completion | Works in the sandbox | `complete.path` resolves paths in the remote workspace, matching where tools and shell commands actually run. |
| Config, model, tools, skills, plugins, rollback, browser surfaces | Expected to route | These methods are implemented by the hosted Hermes gateway and are forwarded by default. Whether a specific feature succeeds depends on sandbox dependencies and configuration. |
| Clipboard image paste | Works | The local proxy reads the laptop clipboard image and uploads bytes to the hosted gateway via `image.attach` with `bytes_b64` and `filename`. |
| Image drag/drop and `image.attach <local-path>` | Works | Local image bytes are uploaded into `$HERMES_HOME/images` in the sandbox. If the path does not exist locally, it is treated as a sandbox path and forwarded unchanged. |
| Maintenance RPC inside Hermes | Works | The hosted Hermes gateway implements `maintenance.run`; it runs cron tick, cache cleanup, paste sweep, session prune, and optionally curator. |

## Should work once Routines payload shape is fixed

| Area | Status | Notes |
|---|---|---|
| Scheduled maintenance wakeups | Blocked on Routine dispatch body | Hermes expects a top-level JSON body like `{"kind":"hermes.maintenance","jobs":["default"],...}`. If Routines still sends `{"input":"<json string>"}`, the current invoke handler rejects it. |
| Per-user scheduled maintenance | Needs correct session targeting | Foundry persistence is keyed by `agent_session_id`. A Routine must invoke the same per-user Foundry session/workspace it is meant to maintain. The JSON `session_id` only routes TUI events; it is not the Foundry workspace key. |
| Maintenance summary in active TUI | Should work when `session_id` is supplied | The maintenance handler emits `maintenance.summary` into the TUI event buffer when a matching TUI session buffer exists. If no TUI is connected, the run still records JSONL history in the sandbox. |

## Partial or real gaps

| Gap | Impact | Notes |
|---|---|---|
| Durable event history and reconnect cursors | Medium/high for remote UX | Current replay is in-memory and bounded. It handles short disconnects and emits replay-gap warnings, but it is not durable across hosted process restarts or long disconnects beyond buffer retention. |
| Generic non-image local file upload | Medium | Non-image drag/drop currently becomes a prompt marker like `[User attached file: ...]`; bytes are not uploaded. This is the real attachment gap, since image upload already works. |
| Idle-time cron/background behavior | Medium | Hermes is not an always-on daemon in this setup. Routines should be the external wake-up clock, and `maintenance.run` should do one bounded pass. Anything that assumes continuous process lifetime needs explicit design. |
| Kanban/background worker maintenance | Open decision | Kanban dispatch is intentionally not part of one-shot maintenance because it can spawn background workers. We need to decide whether that is necessary for unattended remote progress, and if so how to make it bounded and safe. |
| Long-running background workers under hosted suspension | Medium | Work can run while the hosted session is awake, but durability across idle suspension, restart, or reconnect is weaker than in a persistent local daemon unless the worker state is made durable. |
| Optional feature dependencies | Feature-specific | Forwarded RPCs can reach the hosted gateway, but features depending on extra packages, CLIs, credentials, browser services, MCP servers, or provider-specific config only work if those are installed/configured in the container. |

## OK not to have for a TUI-first remote agent

| Area | Why it is OK |
|---|---|
| Voice, local mic, local speakers, TTS playback | These are local-device concerns. They can be added later through explicit local audio proxying, but they are not required for a remote TUI-first workflow. |
| Slack, Discord, Telegram, Matrix, and other chat platforms | Out of scope for now. They can be separate hosted entrypoints later and do not need to block TUI support. |
| Normal text/chat invoke payloads | Not needed if the TUI uses `hermes.rpc` and Routines uses `hermes.maintenance`. Add a separate mapping only if Foundry/Routines prompt entrypoints should behave like chat. |
| Direct laptop filesystem access from remote tools | The sandbox should be treated as the workspace. Laptop access should happen only through explicit proxy/upload paths. |
| Full inheritance of local `~/.hermes` provider config and API keys | The hosted image intentionally uses isolated Foundry config and managed identity. This keeps the remote agent reproducible and avoids leaking local personal settings. |
| Local desktop/browser/computer-use automation | A containerized remote sandbox does not naturally have the user's desktop. Browser/computer-use support should be remote/container-specific if enabled. |

## Practical priority list

1. Fix Routine dispatch so scheduled maintenance sends the exact top-level JSON body Hermes expects, or add a deliberate Hermes unwrap path if the platform must continue sending `{"input":"..."}`.
2. Ensure Routines target the correct per-user Foundry `agent_session_id`/workspace, not just the TUI `session_id`.
3. Harden remote TUI reconnect with durable event logs or durable cursors.
4. Add arbitrary local file upload if TUI users need to attach non-image files from their laptop into the sandbox.
5. Decide whether kanban/background-worker maintenance belongs in the wake-on-demand model, and make it bounded if it does.

## Useful source landmarks

- `third_party/hermes/tui_gateway/foundry_backend.py`: local TUI proxy and `hermes.rpc` client.
- `agent/main.py`: hosted invoke handler, child gateway broker, event buffering, and `hermes.maintenance` dispatch.
- `third_party/hermes/tui_gateway/server.py`: hosted Hermes TUI gateway methods.
- `third_party/hermes/tui_gateway/maintenance.py`: maintenance job implementation.
- `third_party/hermes/tests/tui_gateway/test_foundry_backend.py`: coverage for RPC tunneling, session event subscription, controls, image upload, and slash catalog behavior.
- `third_party/hermes/tests/tui_gateway/test_image_attach_bytes.py`: coverage for remote image byte upload handling.
- `third_party/hermes/tests/tui_gateway/test_maintenance.py`: coverage for maintenance job selection and registration.
