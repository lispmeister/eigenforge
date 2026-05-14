---
id: eig-a6zg
status: closed
deps: []
links: []
created: 2026-05-14T05:02:06Z
type: bug
priority: 2
assignee: lispmeister
---
# Fix recover_pending_commands to resolve all pending commands, not only the last room state row

recover_pending_commands/1 queries latest_room_control_state with LIMIT 1 and recovers at most one pending command per startup. The spec (§9 restart recovery) requires core to classify or terminally resolve every pending command for a room/target/effect before issuing new physical commands. For multi-room configs or a backlog with more than one pending command, recovery will silently miss commands and allow equivalent new commands to be issued.

## Acceptance Criteria

- recover_pending_commands/1 queries all rooms with a non-null pending_command_id
- each recovered pending command is either re-registered with a timer or immediately timed out
- test: two pending commands across two rooms are both resolved on restart
- no equivalent new physical command is issued until all recovered pendings are terminally resolved

