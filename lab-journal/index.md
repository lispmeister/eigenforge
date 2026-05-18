# Lab Journal - Master Index

This is the central table of contents for the Eigenforge lab journal.

The journal is adapted from
<https://github.com/lispmeister/lab-journal>, which follows Howard M. Kanare's
guidelines in *Writing the Laboratory Notebook*. It records engineering
sessions, design decisions, experiments, failures, and verification results
that do not fit cleanly into commit messages.

**Last updated:** 2026-05-18
**Total entries:** 9
**How to maintain:** Add one chronological row every time a journal file is
created.

| Date | File | Key Topics | Milestone / Phase |
|------|------|------------|-------------------|
| 2026-05-08 | [journal-2026-05-08.md](journal-2026-05-08.md) | Added project lab journal workflow adapted from lispmeister/lab-journal | Project process |
| 2026-05-08 | [journal-2026-05-08b.md](journal-2026-05-08b.md) | Added Codex-facing AGENTS.md lab journal instructions | Project process |
| 2026-05-09 | [journal-2026-05-09.md](journal-2026-05-09.md) | Reworked V1 around per-core append-only SQLite command ledgers and aligned spec, trace code, HTML, and tickets | Prototype V1 design |
| 2026-05-10 | [journal-2026-05-10.md](journal-2026-05-10.md) | Clarified Prototype V1 spec ambiguities from SPEC-V1-FIXES-001 and fresh review | Prototype V1 design |
| 2026-05-12 | [journal-2026-05-12.md](journal-2026-05-12.md) | Completed remaining V1 test-gap tickets and verified the umbrella suite | Prototype V1 implementation |
| 2026-05-14 | [journal-2026-05-14.md](journal-2026-05-14.md) | Six bug/task tickets: exqlite migration, dual stale-path events, all-room restart recovery, observe/2 snapshot status, core_node_id from opts, interpret_fault nil-default removal | Prototype V1 correctness |
| 2026-05-14 | [journal-2026-05-14b.md](journal-2026-05-14b.md) | Fresh-eyes review: 7 implementation gaps (trace stale divergence, fan-seq columns, SQL parameterization, non-atomic writes, startup verification, redundant init, cond catch-all) and 3 spec ambiguities (no-op clause, stale payload type, effect_epoch definition); 10 tickets filed | Prototype V1 review |
| 2026-05-15 | [journal-2026-05-15.md](journal-2026-05-15.md) | Finished the shortest V1 path, regenerated trace goldens, fixed a leaked test secret, and verified the full suite green | Prototype V1 completion |
| 2026-05-18 | [journal-2026-05-18.md](journal-2026-05-18.md) | Surveyed specification systems, chose layered traceable Markdown for V1, and applied stable IDs, rule tables, trace coverage, and a traceability index to the Prototype V1 spec | Specification language |

## Attachments / Supporting Materials

Attachments go in `lab-journal/attachments/` with date-prefixed filenames.

No attachments yet.

## Archival Note

Periodically snapshot the `lab-journal/` directory into a release artifact or
other durable archive. The journal is an engineering record, not the
authoritative runtime control ledger.
