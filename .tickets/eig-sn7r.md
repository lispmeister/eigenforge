---
id: eig-sn7r
status: open
deps: []
links: []
created: 2026-05-14T00:00:00Z
type: task
priority: 2
assignee: lispmeister
---
# Extract IO.SnapshotNormalizer from HomeAssistantAdapter (§2)

The spec (§2) lists `IO.SnapshotNormalizer` as a separate module in the suggested OTP process layout. Currently normalization logic lives in `HomeAssistantAdapter.normalize_snapshot/3` (and implicitly in `SimulatorClient`), making it harder to test normalization in isolation and conflating adapter-specific translation with the shared contract normalization logic.

Required changes:
1. Create `apps/eigenforge_io/lib/eigenforge/io/snapshot_normalizer.ex` with a `normalize/2` (or `normalize/3`) function that accepts raw state maps and normalization options and returns `{:ok, NormalizedSnapshot.t()} | {:error, reason}`.
2. Move the core normalization and freshness-computation logic from `HomeAssistantAdapter.normalize_snapshot/3` into `IO.SnapshotNormalizer`.
3. `HomeAssistantAdapter` calls `IO.SnapshotNormalizer` for normalization and retains only HA-specific entity-id mapping.
4. `SimulatorClient` calls `IO.SnapshotNormalizer` for any normalization it performs.
5. Add or update unit tests that cover normalizer logic directly without going through the adapter.

## Acceptance Criteria

- `IO.SnapshotNormalizer` module exists with a normalizer function.
- `HomeAssistantAdapter` and `SimulatorClient` use it.
- Normalizer is unit-tested independently of the adapter.
- `mix test` green.
