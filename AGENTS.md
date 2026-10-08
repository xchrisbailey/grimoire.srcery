## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues for `xchrisbailey/grimoire.srcery`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

Use a single-context layout. See `docs/agents/domain.md`.

### Git workflow

Write each commit subject as a plain imperative sentence, the way the history does: `Speed up CI: cache builds, one iOS slice, parse speed on main only`.
Commit and push completed changes to the GitHub remote. Before pushing, check the working tree and confirm the branch is up to date with its remote counterpart.

### Orchestration

The main session (Opus 5.5) plans, delegates, reviews, and merges; all coding and test writing goes to the `coder` agent. A session spawned as a `coder`, `reviewer`, `shepherd`, `scout`, or `adversary` follows its own file in `.claude/agents/` instead. When delegating a ticket, starting an agent team, or reviewing a coder's branch, read `docs/agents/orchestration.md`.

### Coding standards

Review a diff against `CODING_STANDARDS.md`.
