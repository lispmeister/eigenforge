**Step-by-Step Guide: Mastering AI-Assisted Elixir Development (Claude Code, Cursor, Codex & Friends)**

The Elixir Forum’s Dev Env / Tools / AI category is packed with battle-tested advice from developers using Claude Code (the current standout), Cursor, Codex/Copilot, and similar tools. The consensus: **Elixir becomes a “cheatcode” for AI coding** when you stop treating the AI like a generic coder and instead give it structured, idiomatic guidance via skills, plugins, hooks, and project rules. Without this, AI produces non-idiomatic code (Python/TS patterns, missing `@impl true`, weak tests, security holes). With it, you get higher-quality, testable, maintainable output that passes Credo/Dialyzer and requires far less cleanup.

Here’s the distilled, actionable guide compiled from the top threads (Elixir Skills for Claude/Cursor/Codex, Sharing My Claude Code Plugin, Here’s how I’m coding Elixir with AI, Opinionated Claude integration, and related discussions).

### Step 1: Set Up the Foundation (.claude Directory + CLAUDE.md)
1. In your project root (or `~/.claude` for global reuse), create a `.claude/` folder. Most tools (Claude Code, Cursor, Copilot, OpenCode, even Gemini with minor tweaks) automatically load from here.
2. Add a `CLAUDE.md` (or `AGENTS.md`) file in the project root. This is your “constitution” for the AI.
   - Include **Engineering Principles** (security-first, no demo code, fail fast, make illegal states unrepresentable, YAGNI, TDD).
   - Add a **Definition of Done** checklist: All tests pass (`mix test`), Dialyzer passes, Credo passes, no warnings.
   - Reference project-specific context (contexts, domains, custom conventions).
   - Example starter (from forum users):
     ```
     # CLAUDE.md
     This file provides guidance to Claude Code...
     ## Engineering Principles we Follow
     - Security first...
     - Never write demo code → always start with a failing test...
     - Use compile-time checking...
     ## Definition of Done
     1. All tests pass (mix test)
     2. Dialyzer passes (mix dialyzer)
     3. Credo passes (mix credo)
     ```
3. (Optional but recommended) Copy a `CLAUDE.md.template` from the phoenix-guide repo and customize it.

This alone dramatically reduces hallucinations and drift.

### Step 2: Install Elixir-Specific Skills (Teach the AI Idiomatic Elixir)
Skills are contextual knowledge files that load only when needed—far more efficient than bloating context with a giant prompt.

1. Use the **official marketplace** (easiest):
   ```
   /plugin marketplace add j-morgan6/elixir-phoenix-guide
   ```
   Then run `/plugin` → install/verify (scope: user or project). Update the same way.

2. Or manually: Clone/copy the 19 skills from https://github.com/j-morgan6/elixir-phoenix-guide (or the earlier elixir-claude-optimization repo) into `.claude/skills/`.

Key skills included (v2.3+):
- `elixir-essentials` (pattern matching, pipes, `with`, tagged tuples)
- `phoenix-liveview-essentials`, `ecto-essentials`, `testing-essentials`, `otp-essentials`, `security-essentials`, `phoenix-channels-essentials`, etc. (19 total)

Each skill has non-negotiable RULES sections + auto-suggest/file-pattern detection (e.g., auto-load testing skill for `_test.exs` files).

**Pro tip**: Skills now support `INVOKE BEFORE` directives and sub-agent injection so Claude discovers and applies them proactively.

### Step 3: Add Hooks for Real-Time Validation (The Game-Changer)
Hooks run automatically on file changes/edits and block or warn on anti-patterns.

1. The `elixir-phoenix-guide` plugin installs **27 hooks** automatically (via `hooks-settings.json`).
   - **Blocking** (exit 2, stops bad code): missing `@impl true`, `String.to_atom/1` on user input, unparameterized SQL fragments, unsafe redirects, hardcoded paths/config, dangerous mix commands.
   - **Warnings** (exit 1): nested `if/else` (use `case`), inefficient `Enum` chains, debug statements, sensitive logging, raw HTML, timing attacks.
   - **Post-tool-use** (after edits): code-quality analysis (duplication, ABC complexity, unused functions, HEEx template dupes), missing preloads, context-boundary violations.
   - **SessionStart**: auto-detects Phoenix/LiveView/Ecto/Oban version and adapts rules.

2. For even tighter integration, add the **Opinionated Claude** Mix library:
   - Add `{:claude, "~> 0.2"}` to `mix.exs`.
   - Run `mix claude.install` → auto-adds formatting/compile/dependency hooks + Tidewave MCP support.
   - Hooks now run `mix format`, `mix compile`, etc., after every AI edit.

Result: Claude self-corrects *before* you even review the code.

### Step 4: Configure Context Management & Workflow Tools
1. Add a **Prepare for Handoff** skill (or use the one in elixir-claude-optimization). It creates/updates `HANDOFF.md` with a mini-prompt, then you `/clear` context and resume fresh.
2. Use sub-agents for specialized tasks (testing, security audit, etc.).
3. (Advanced) Install **Giulia** (Elixir daemon): https://github.com/thatsme/giulia. It gives the AI AST-level intelligence—dependency graphs, cycle detection, change-risk analysis, semantic search—so it stops treating your codebase as plain text.
4. Optional: Tidewave MCP server (for Phoenix) + Obsidian `/docs` vault for AI-generated plans/checklists.

### Step 5: Adopt the Daily Workflow (Lessons Learned)
- **Treat AI like a very fast junior dev**: Steer with short, focused prompts. Restart context often. Verify *everything* (especially OTP supervision, concurrency, error handling).
- **Enforce TDD**: Always start with a failing test. The `testing-essentials` skill scaffolds proper DataCase/ConnCase/LiveView tests.
- **Run gates religiously**: After AI changes, the hooks already check format/compile; manually run `mix test`, `mix dialyzer`, `mix credo`.
- **Security & quality first**: Hooks catch 90 % of common pitfalls (SQL injection, atom exhaustion, XSS, open redirects).
- **Iterate aggressively**: Use `/status` for token usage; clear context when it drifts.
- **Measure impact**: Users report 10x productivity, 28+ passing tests generated automatically, excellent Credo scores, and far fewer post-AI refactors.

### Bonus Resources from the Forum
- **Core plugin**: https://github.com/j-morgan6/elixir-phoenix-guide (19 skills + 27 hooks)
- **Earlier version / skills collection**: https://github.com/j-morgan6/elixir-claude-optimization
- **Opinionated integration**: https://github.com/bradleygolden/claude (mix claude.install)
- **Cheezy’s full AI environment post** (cross-posted on forum): https://cheezyworld.ca/post/my_dev_environment (covers editor configs, Tidewave, usage rules)
- Forum category for ongoing discussion: https://elixirforum.com/c/wikis-polls/dev-env-tools/152 (filter by “ai” or “claude-code”)

Start with Steps 1–3 today (it takes ~15 minutes) and you’ll immediately see cleaner, more idiomatic Elixir from Claude/Cursor/Codex. The community’s biggest takeaway: **invest once in skills + hooks, and the AI stops fighting Elixir idioms and starts amplifying them**. Drop your current IDE/setup in a reply if you want links to even more targeted configs!

