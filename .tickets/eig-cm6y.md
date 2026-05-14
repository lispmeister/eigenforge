---
id: eig-cm6y
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 4
assignee: lispmeister
---
# Add Mailbox.ChannelManager (§2 OTP layout)

The spec (§2) lists `Mailbox.ChannelManager` in the suggested OTP process layout:

> "`eigenforge_mailbox` … Manages channels, topics, lightweight notifications, and supported read projections."

Currently there is no channel management module. Topic registration and dispatch happen inline in `CommandPublisher` via raw `Registry` calls. A `ChannelManager` centralises topic lifecycle and makes the mailbox boundary between core, IO, and dashboard explicit.

Required changes:
1. Create `apps/eigenforge_mailbox/lib/eigenforge/mailbox/channel_manager.ex` as a GenServer or supervision helper that owns topic registration, subscriber tracking, and dispatch for mailbox topics (e.g., `"commands:io"`).
2. `CommandPublisher` delegates topic dispatch to `ChannelManager` rather than calling `Registry.dispatch` directly.
3. `HomeAssistantClient` subscribes to command topics via `ChannelManager` rather than `CommandPublisher.subscribe` or raw Registry.
4. Add tests for topic registration, dispatch, and subscriber lifecycle through `ChannelManager`.

## Acceptance Criteria

- `Mailbox.ChannelManager` module exists and manages the `"commands:io"` topic.
- `CommandPublisher` and `HomeAssistantClient` use it.
- `mix test` green.
