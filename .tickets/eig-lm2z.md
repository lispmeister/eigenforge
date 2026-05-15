---
id: eig-lm2z
status: closed
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 1
assignee: lispmeister
---
# Add mix eigenforge.ledger.migrate (§4 required)

The spec (§4) explicitly requires a migration tool stub:

> "A no-op migration tool stub reserves the migration interface and makes accidental schema drift fail loudly: `mix eigenforge.ledger.migrate --from 1 --to 1`"

> "In V1, this task asserts that every ledger payload has `schema_version=1` and exits 0. For any other `--to` value it exits non-zero with a clear `no V1→VN migration defined` message. Do not use schema workarounds that bypass this check; add a real migration task instead."

This task does not exist anywhere in the codebase. Without it, schema drift fails silently or produces cryptic errors rather than a clear migration-required message.

Required changes:
1. Create `apps/eigenforge_core/lib/mix/tasks/eigenforge.ledger.migrate.ex`.
2. Parse `--from` and `--to` args.
3. When `--from 1 --to 1`: scan all ledger payloads in the configured SQLite db and assert each has `schema_version=1`, exit 0 on success.
4. For any other `--to` value: exit non-zero with `"no V1→VN migration defined"`.
5. Add a test in `apps/eigenforge_core/test/eigenforge/mix_tasks/ledger_tasks_test.exs` covering both code paths.

## Acceptance Criteria

- `mix eigenforge.ledger.migrate --from 1 --to 1` exits 0 on a valid V1 ledger.
- `mix eigenforge.ledger.migrate --from 1 --to 2` exits non-zero with the required message.
- Task is tested in the ledger tasks test file.
- `mix test` green.
