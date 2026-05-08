# Agent Instructions

## Lab Journal

Eigenforge uses a structured engineering lab journal for sessions that change
code, specs, architecture, or durable project decisions.

This workflow is adapted from
<https://github.com/lispmeister/lab-journal>, which follows Howard M. Kanare's
laboratory notebook principles: permanence, immediacy, self-containment,
completeness, and witnessing.

## Starting A Session

1. Copy `lab-journal/TEMPLATE.md` to `lab-journal/journal-YYYY-MM-DD.md`.
   Append `b`, `c`, and so on for multiple entries on the same date.
2. Fill in date, session goals, and known context before starting work.

## During A Session

- Record observations, decisions, commands, errors, and results as the session
  proceeds.
- Use tables for structured data such as issue/fix lists, test results,
  tradeoffs, and before/after measurements.
- Fill in the Hypothesis vs Measured Impact table whenever the work is
  testable. State the expected outcome before running the verification.
- Record failures, rejected approaches, and rollbacks. They are part of the
  experimental record.
- Link to commits, specs, issue IDs, command output, and artifacts rather than
  duplicating everything in prose.

## Ending A Session

Fill in the footer block:

- `Signed / Date`: full ISO timestamp.
- `Participants & Tools`: people, agent/model, language/runtime versions, and
  notable tools.
- `Commit / Witness`: commit hashes or pending witness information.
- `Related Specs / Issues`: specs, issues, beads, or other durable references.
- `Next journal entry`: expected next filename.

After committing, update `lab-journal/index.md` with one chronological row for
the entry.

## Rules

- Entries are append-only. Do not delete or rewrite history. Add a dated
  correction that references the original entry when needed.
- Each entry should stand alone well enough for a future reader to understand
  what was attempted, what happened, and what was concluded.
- Attachments go in `lab-journal/attachments/` with date-prefixed filenames.
- The journal is non-authoritative for Eigenforge control decisions. It is a
  human engineering record; the durable runtime ledger remains the authority
  for control events.
