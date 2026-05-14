# Agent Instructions

## Task Tracking

This project uses the Ticket CLI (`tk`) for task management.

- Always use `tk` commands. Never use markdown TODO lists or Beads.
- Run `tk ready` to list open/in-progress tickets whose dependencies are resolved.
- Run `tk show <id>` to read a ticket's full description and acceptance criteria before starting work.

### Creating tickets

Title is a **positional argument**, not a flag:

```
tk create "Title here" -t task -p 1 -a lispmeister \
  -d "Description" \
  --acceptance "Acceptance criteria"
```

Types: `bug` | `feature` | `task` | `epic` | `chore`
Priority: `0` (highest) → `4` (lowest). P1 = `-p 1`, P2 = `-p 2`, etc.

### Working a ticket

```
tk start <id>              # mark in_progress when you begin
tk add-note <id> "text"    # record progress or observations mid-session
tk close <id>              # mark closed when acceptance criteria are met
```

Partial ID matching works: `tk show igam` resolves to `eig-igam`.

## Lab Journal

Eigenforge has a structured engineering lab journal for recording selected
sessions.

This workflow is adapted from
<https://github.com/lispmeister/lab-journal>, which follows Howard M. Kanare's
laboratory notebook principles: permanence, immediacy, self-containment,
completeness, and witnessing.

## When To Use It

Only create or update lab journal entries when the user explicitly asks for a
journal entry, asks to use the lab journal, or asks to record the session.

Do not create or update journal files by default for ordinary code, spec,
architecture, or project-decision work.

## Starting A Requested Journal Entry

1. Copy `lab-journal/TEMPLATE.md` to `lab-journal/journal-YYYY-MM-DD.md`.
   Append `b`, `c`, and so on for multiple entries on the same date.
2. Fill in date, session goals, and known context before starting work.

## During A Requested Journal Entry

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

## Ending A Requested Journal Entry

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
