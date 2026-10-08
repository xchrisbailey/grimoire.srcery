# Orchestration

**Roles.**

- **Opus 5.5** (`claude-opus-5-5`) is the main session, and the lead of an agent team. It plans, breaks work into tickets, delegates, reviews, and decides. Orchestration and the review verdict are never delegated.
- **Sonnet 5.5, high reasoning** (`claude-sonnet-5-5`, `high`) does all delegated coding and test writing, through the `coder` agent in `.claude/agents/coder.md`.
- On an agent team, three more agents in `.claude/agents/` take work off the lead:
  - `reviewer` (Sonnet 5.5, high) gives each coder's branch a first-pass review;
  - `shepherd` (Haiku 5.5) reruns the local checks on a coder's branch and cleans up after merges;
  - `scout` (Haiku 5.5) is a read-only lookup subagent for gathering what a brief needs. It works in either mode.
- **Fable 5.1** (`claude-fable-5-1`) runs the `adversary` subagent, which tries to break a ticket breakdown or a risky branch. Opus calls it; it is never a teammate.
- Opus fixes trivial review nits itself. Anything larger goes back to a coder.
- When a spec or ticket records execution assignments, it uses these roles unless the user names others for that work.

**Delegation.**

- Each delegated task is confined to one ticket, or one clearly bounded piece of one.
- Run it in a subagent or a new thread with its own git worktree and branch.
- The brief must stand alone. Include:
  - the ticket link and its acceptance criteria;
  - the relevant ADRs and `GLOSSARY.md` terms;
  - what is out of bounds;
  - the build and test commands;
  - what to report back: the branch, a summary, and anything left open.
- Coders don't widen scope or make product or architecture decisions. They stop and report any open question to Opus.
- A coder that goes idle with checks still running may never wake to report. When one says it is waiting on a run, Opus watches the branch head or the run's output itself, with a background wait, and doesn't wait on the coder's message alone.

**Agent teams.**

- Delegate a single ticket to a `coder` subagent. Start an agent team when two or more tickets are ready at once. A team costs tokens for every teammate, so it has to buy parallel work.
- The roster is up to three coders, one `reviewer`, and one `shepherd`. Spawn each from its agent type, which sets its model, and name each coder `coder-<issue>`.
- A teammate starts in the main checkout with none of the lead's conversation. The brief still stands alone, and a coder's brief also names its branch, its worktree path `.claude/worktrees/<issue>-<slug>`, and its base.
- The main checkout stays on `main` and clean. Only the lead works in it.
- Give each ticket three tasks, each subject starting with `#<issue>`, and each depending on the one before:
  - `#<issue> code`, for its coder;
  - `#<issue> review`, for the reviewer;
  - `#<issue> verify`, for the shepherd.
  A ticket's `code` task also depends on the `code` task of each ticket that blocks it.
- The coder and reviewer settle first-pass findings between themselves. A question about the spec, an ADR, or product behaviour comes to the lead from either of them.
- Teammates don't survive `/resume`, so GitHub holds everything that matters: coders push their branch early, and the reviewer posts findings as a comment on the ticket. Brief a replacement teammate from the branch and the ticket's comments.
- Shut a teammate down once its tasks are completed.

**Adversarial pass.**

- Run the `adversary` subagent at two points:
  - on the ticket breakdown, before delegating work that spans two or more tickets;
  - on a ticket's branch, before the Opus review, when it touches saving or external-change handling (`OpenDocument`, `Workspace/`), the parser, serialization, or the block index, `VersionStore`, or the shape of something an installed build has stored (`projects.json`, a preferences key).
- Give it the tickets or the branch and the spec. Keep your own conclusions and the reviewer's pass out of the brief, so its read isn't anchored on them.
- A finding counts when it comes with a scenario that reproduces it. Opus decides each one: fix the breakdown, send it to the coder, or set it aside with the reason on the ticket.

**Review.**

- Opus reviews every ticket's branch before it is merged, checking it against:
  - the ticket's acceptance criteria;
  - the spec and ADRs;
  - the glossary;
  - `CODING_STANDARDS.md` and `AGENTS.md`.
- Opus also confirms that both app schemes build, the package tests pass, and lint is clean. The coder runs the checks listed in `docs/development.md` and quotes the final `** BUILD SUCCEEDED **` line of each build and the final `Test run with … passed` line of each package, and Opus reruns them on the ticket's branch before merging it, or on a team reads the shepherd's `verify` result for the branch's current head. A report without those lines doesn't count. When the branch has a pull request, its CI run is green before the merge as well.
- On a team, the `reviewer` passes a branch before Opus reviews it. Its pass covers the coding standards, the glossary, and the acceptance criteria; the spec, the ADRs, and the verdict stay with Opus.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- Opus reports the result to the user.
