---
id: eig-c2fz
status: closed
deps: [eig-60h5]
links: []
created: 2026-05-09T14:10:27Z
type: feature
priority: 1
assignee: lispmeister
tags: [next-slice]
---
# Implement runtime config and mode selection

Implement V1 runtime config for EIGENFORGE_IO_MODE, EIGENFORGE_CORE_NODE_ID, EIGENFORGE_CORE_DB_PATH, EIGENFORGE_HMAC_SECRET, EIGENFORGE_AFTER_ACTION_TIMEOUT_MS, HA reconnect max, and IO fault log path. Config should support simulator and home_assistant modes without connecting to outside services in simulator mode.

## Acceptance Criteria

Config loads from env/runtime config; simulator mode does not require Home Assistant values; home_assistant mode fails fast on missing HA URL/token/entity ids/HMAC secret; static HA entity domains are plausibility-checked before connect while dynamic entity existence/class validation happens after HA connects; tests cover required/missing config cases and exactly-one-active-room validation.


## Notes

**2026-05-10T05:09:28Z**

2026-05-10 spec clarification update: runtime mode selection must follow the startup behavior matrix: fail fast for invalid config/secrets, ignore HA settings in simulator mode, and distinguish recoverable HA connectivity failures from startup validation failures.

**2026-05-10T05:37:28Z**

SPEC-V1-FIXES-003 applied: config validation must enforce exactly one active V1 room and fail startup on unsupported schema_id/schema_version/format_version in runtime config, sidecars, generated contracts, or existing ledger payloads.

**2026-05-10T06:02:11Z**

Implemented Eigenforge.Core.RuntimeConfig with pure env-map loading for simulator/home_assistant modes, required common env validation, HA static config/domain validation without external connections, numeric defaults/validation, and exactly-one-active-room device inventory validation. Added focused tests for simulator mode, HA missing/static domain failures, valid HA config, invalid mode/integer config, and active room counts. Verified mix test, mix compile --warnings-as-errors, mix run tools/smoke_contracts.exs, git diff --check, and tk dep cycle.
