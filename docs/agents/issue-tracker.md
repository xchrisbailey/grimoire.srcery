# Issue tracker: GitHub

Issues and specs for this repo live in GitHub Issues at `xchrisbailey/grimoire.srcery`. Use the `gh` CLI for issue operations.

## Conventions

- Create: `gh issue create --title "..." --body "..."`. Use `--body-file` for longer bodies.
- Read: `gh issue view <number> --comments`, including labels when relevant.
- List: `gh issue list --state open --json number,title,body,labels,comments`; add state and label filters as needed.
- Comment: `gh issue comment <number> --body "..."`
- Apply or remove a label: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

Run `gh` inside this clone so it identifies the repository from the Git remote.

## Pull requests as a triage surface

**PRs as a request surface: no.**

If changed to `yes`, triage external PRs through the same states and labels. Use `gh pr view`, `gh pr list`, `gh pr comment`, `gh pr edit`, and `gh pr close`. Review a PR's diff with `gh pr diff`. GitHub shares issue and PR numbers, so resolve an ambiguous `#<number>` before acting.

## Skill instructions

When a skill says "publish to the issue tracker", create a GitHub issue. When it says "fetch the relevant ticket", use `gh issue view <number> --comments`.

A spec's single home is its file under `docs/specs/`. When a skill says to publish a spec, write the file, then create the issue with the Problem Statement, the Solution, and a link to the file. Tickets and briefs point at the file.

## Wayfinding operations

For `/wayfinder`, keep the map as one issue labeled `wayfinder:map` and create child tickets as GitHub sub-issues. If sub-issues are unavailable, link children in a task list in the map body and put `Part of #<map>` in each child. Use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task` for child types.

Represent blockers with GitHub's native issue dependencies. If unavailable, put `Blocked by: #<number>` at the top of the child issue. An unblocked, unassigned open child is ready to claim. Claim it with `gh issue edit <number> --add-assignee @me`. After resolving it, comment with the answer, close it, and add a context pointer to the map's decisions.

## Sub-issues and blocking edges

`/to-tickets` and `/wayfinder` both use these. `gh` has no subcommand for either, so call the API. Both calls take the other issue's numeric database id, not its `#number` or `node_id`:

```sh
gh api repos/xchrisbailey/grimoire.srcery/issues/<number> --jq .id
```

- Add a sub-issue: `gh api --method POST repos/xchrisbailey/grimoire.srcery/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`
- Add a blocker: `gh api --method POST repos/xchrisbailey/grimoire.srcery/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`
- Read open blockers: `gh api repos/xchrisbailey/grimoire.srcery/issues/<number> --jq .issue_dependencies_summary.blocked_by`. A ticket is unblocked when this is `0`.

Publish blockers before the tickets they block, so each edge has a real id to point at.
