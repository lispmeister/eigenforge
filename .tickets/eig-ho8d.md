---
id: eig-ho8d
status: open
deps: []
links: []
created: 2026-05-14T05:54:37Z
type: bug
priority: 2
assignee: lispmeister
---
# Verify ledger hash chain at startup before processing new snapshots

LedgerWriter.prepare_ledger/3 (ledger_writer.ex:199-209) checks whether the ledger is empty and creates a genesis if so, but does not verify the existing hash chain when the ledger is non-empty. Spec §9 requires core to verify the local ledger hash chain before processing new snapshots. The mix eigenforge.ledger.verify task exists and does the verification, but nothing calls it at startup.

## Acceptance Criteria

LedgerWriter.init or prepare_ledger calls the ledger verifier against the existing chain before the writer enters the running state. Startup fails (GenServer stops with a descriptive reason) if hash chain verification fails. A test exercises startup with a tampered ledger and asserts the supervisor stops the writer. The existing test suite passes unchanged.

