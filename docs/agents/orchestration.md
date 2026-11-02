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

**Skills.**

- These roles override a skill's own wording about who does the work. A skill's "implementer subagent" is a `coder`, its "exploration subagent" is a `scout`, and its "merger subagent" is Opus.
- A skill that writes code or tests meant to merge (`/implement`, `/implement-spec`, `/tdd`) runs that work through a `coder`. Opus doesn't write it in the main checkout, and "commit to the current branch" means the coder's branch.
- `/implement-spec` may use an integration branch. Opus keeps it in its own worktree under `.claude/worktrees/`, names it as the base in each coder's brief, and merges each reviewed ticket branch into it. The review, the checks, and the adversarial pass below apply to each ticket branch, and again to the integration branch before it merges to `main`. The integration branch runs `scripts/check.sh` after each ticket merge into it, and `scripts/check.sh --core-runs 10` before it merges to `main`.
- `/tdd` wants its seams confirmed with the user, and a coder can't ask. The seams in the spec's Testing Decisions count as confirmed, and the brief points at them. A coder that needs a seam the spec doesn't name stops and reports it.
- Throwaway code is the exception: Opus may write a `/prototype` or a `/diagnosing-bugs` reproduction itself, in a scratch worktree that is never merged. The fix or the real implementation goes to a coder.

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
- Coders run `scripts/check.sh` in the foreground, so their report arrives with the result. The lead reads `build/check-logs/<sha>/summary.txt` in the coder's worktree for the head under review.

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

- Run the `adversary` subagent at three points:
  - on the ticket breakdown, before delegating work that spans two or more tickets;
  - on a ticket's branch, before the Opus review, when it touches saving or external-change handling (`OpenDocument`, `Workspace/`), the parser, serialization, or the block index, `VersionStore`, or the shape of something an installed build has stored (`projects.json`, a preferences key);
  - on an integration branch at its first checkpoint, and again at its last.
- Give it the tickets or the branch and the spec. Keep your own conclusions and the reviewer's pass out of the brief, so its read isn't anchored on them.
- A finding counts when it comes with a scenario that reproduces it. Opus decides each one: fix the breakdown, send it to the coder, or set it aside with the reason on the ticket.

**Review.**

- Opus reviews every ticket's branch before it is merged, checking it against:
  - the ticket's acceptance criteria;
  - the spec and ADRs;
  - the glossary;
  - `CODING_STANDARDS.md` and `AGENTS.md`.
- Opus also confirms that both app schemes build, the package tests pass, and lint is clean. The coder runs `scripts/check.sh` and reports the contents of `build/check-logs/<sha>/summary.txt`. Opus reads the summary for the branch's current head, or on a team the shepherd's `verify` result, and runs the script itself when there is none. A report without the summary of the branch's current head doesn't count.
- A non-model failure is real until it has a ticket or a measured cause; the word "flake" needs one of those. Only the model-gated suites in `docs/development.md` get a rerun.
- On a team, the `reviewer` passes a branch before Opus reviews it. Its pass covers the coding standards, the glossary, and the acceptance criteria; the spec, the ADRs, and the verdict stay with Opus.
- Review findings go back to the same coder, which keeps its context, until the review passes.
- Opus reports the result to the user.

**Merging to main.**

- Run `scripts/check.sh` on the merge result at a clean head; the `pre-push` hook refuses `main` without it. A pull request is optional.
