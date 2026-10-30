# Development

Grimoire is a native markdown editor for macOS with an iOS companion. It requires Xcode 27 with the macOS 27 and iOS 27 SDKs, XcodeGen, and SwiftLint. `README.md` covers the layout, opening the project, and packaging a release.

## Checks

Run these from the root of the checkout or worktree before a branch is reviewed or merged. `Grimoire.xcodeproj` is generated and not checked in, so a fresh worktree has none until the first command runs.

```sh
xcodegen generate
xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireMac -destination 'platform=macOS' -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireiOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
(cd Packages/GrimoireCore && swift test)
(cd Packages/GrimoireEditor && swift test)
(cd Packages/GrimoireIntelligence && swift test)
xcrun swift-format lint --strict --recursive Apps Packages
swiftlint --strict
python3 scripts/test-dmg-layout.py
```

Each build ends in `** BUILD SUCCEEDED **` or `** BUILD FAILED **`, and each package in a `Test run with … passed` or `… failed` line. When clean, `swift-format` prints nothing and SwiftLint ends in `Found 0 violations`. The last command checks the DMG window layout writer and ends in `OK`; it needs only the Python 3 that macOS and the CI runner provide.

The suites in `GrimoireIntelligence` gated on `modelIsReady` run the real on-device model, so they only run on a Mac that has it, and its output varies from run to run. `WritingEvaluations` fails now and then on unchanged code. When one of those suites fails, rerun the package: a pass on the rerun counts, reported with both result lines and the name of the test that failed. A failure anywhere else, or one that repeats, is a real failure.

Derived data (`build/DerivedData`) and each package's `.build` sit inside the checkout, so runs in separate worktrees don't share a build. The first build in a worktree fetches and compiles the tree-sitter grammars, which takes a few minutes and needs a network connection.

The timing tests assume a local Apple silicon Mac. On a slower machine, set `GRIMOIRE_PERF_BUDGET_SCALE` to stretch their budgets, as CI does.

`WKWebView` never loads inside `swift test`, so PDF export and print can't be covered there. Check them in the built Mac app.

## Content template configuration demo

In the Mac app, bind a folder to a project and save an ordinary Markdown file inside it
(a separate bound templates folder also works). Right-click a root or subfolder,
choose **Content Template…**, then **Use a template** → **Choose Existing File…**.
The sheet shows the effective owning/inherited-from folder and saved template source.
Close and reopen the sheet, then relaunch to check persistence. Several folders can
choose the same source.

Manual QA still needs to check the native picker and sandbox access: cancel a
replacement, choose an invalid or outside-project source, and simulate a settings
save failure. Each must leave the previous choice unchanged and a failed edit
must explain how to recover. Check that a second project using the same folder
starts unconfigured. Choosing an existing source must not modify its contents or
create files in content folders. Broken-source recovery checks are listed below.

**Use a template → Create Template…** asks for a Markdown save location in an
active project binding. It creates an empty ordinary source even in a templated
destination, then persists the assignment and opens the editor at the empty end.
Existing filenames use numbered suffixes, never replacement. Cancelling or failed
publication keeps the old choice. A settings-save failure preserves the published
source and old choice, reports the source's path, and offers **Open Created Source**;
repair settings and use **Choose Existing File…** rather than creating another copy.
**Edit Template** opens the effective source, including an inherited source, using
ordinary document selection without rewriting it or changing its assignments.
Creating a source assigns only the edited folder; it never replaces an ancestor's choice.

Native save/open picker, Edit Template selection, post-dismissal editor focus and
caret acceptance remain **UNVERIFIED**. Check invalid/unbound/symlink destinations,
cancel, collision protection, assignment persistence failure, and source opening.
Check reuse across folders, saved versus unsaved edits, and unchanged existing
documents in the app too; package regressions do not establish native UI acceptance.

New File uses the nearest active explicit choice within the destination's most-specific
bound root. **Inherit** removes only the edited folder's explicit choice;
**Use a template** replaces inherited content; **No template** disables it for
descendants until a deeper source choice. A separately bound inner folder starts
unconfigured and masks, but retains, outer assignment records. Equivalent-depth
aliases use project order. A broken inherited source blocks creation and identifies
its owning folder rather than falling back. Unresolved choices remain inactive.

Native checks for all three choices and effective owner/source display are
**UNVERIFIED**. Check a root assignment inherited by descendants, a nearer override,
an opt-out and a deeper re-enable. Choose Inherit on an unconfigured descendant and
confirm its ancestor choice is not deleted. Also check Inherit after an override,
save-failure preservation, overlapping-root masking, project isolation, and an
unavailable inherited source's owner display. No native GUI tools are available;
package integration tests and compiled UI wiring do not verify these interactions.

Menu/shortcut and palette commands resolve their existing destination before joining the same
creation flow as the folder context menu. The naming sheet shows destination and
source, edits a literal stem with `.md` separate, and creates nothing on cancel.
Relevant context changes require another confirmation; saved edits to the same
source remain live. Content placeholders now expand once for the allocated filename
and one local attempt timestamp. `{title}`, `{filename}`, `{date}`, and `{time}`
support explicit `:yaml` string forms; doubled braces escape them literally.
Untouched filename suggestions refresh at confirmation and user-visible retry;
edited stems remain literal. Collision retries keep the same saved source and time.

Native Mac acceptance is **not verified** by package tests or source wiring. Check
each real menu, shortcut, palette, and folder-context route: destination/source
display, invalid names without rewriting, cancellation, context review preserving
input, collision suffixes, no preview or second rename prompt, and focused editor
with its caret at the UTF-16 content end (including emoji and a BOM). Check an open
or last-opened-settings failure after publication separately: preserve the created
file and do not retry creation. No native GUI automation harness is available.
Check creation with an unrelated document selected: only the actual destination's
effective choice should apply.

Placeholder-specific native QA is **not verified**: use a source with all four raw
and YAML-safe forms, doubled braces, and unknown forms. Leave an untouched generated
name open across midnight, then confirm; repeat with an edited literal name. Check
matching filename/content dates, collision suffixes in inserted titles and filenames,
and the focused caret at the expanded content end. Rename/move the created document
and verify its content and source remain unchanged. Package tests cover the Core
creation outcomes, not these native interactions.

Also check destination review without a template: prepare creation in an unassigned
folder, replace that directory before confirmation, review the updated destination,
then confirm. Success must dismiss the review sheet and hand off once after dismissal,
even though this output keeps legacy preview behavior. A repeated confirmation must
not leave a stale sheet, create another document, or open the result twice. Direct
legacy creation without a sheet must still open immediately and offer its usual rename.

### Broken-source recovery

Native recovery acceptance remains **UNVERIFIED**. In each New File route, remove a
configured source, revoke its access, point its saved reference outside the project's
bound folders, or save invalid UTF-8/NUL bytes. The naming sheet must identify the
broken source and reason (including its root/reference when no live URL is available),
without using an ancestor, cached content, or empty content automatically.
While the workspace stays open, move an entire separately bound source folder out
of its recorded location without changing its bookmark. After any context review,
both an already-open naming sheet and a new New File command must reach source
recovery. The still-valid destination must allow explicit empty-once creation or
repair to an eligible replacement. Restoring source-root availability requires
another review; losing the destination root must still block creation and repair.

Check **Retry**, **Choose Replacement…**, **Create Empty Once**, and **Cancel**.
Retry must preserve an edited name, reread saved bytes, refresh untouched generated
names/date/time, and recheck collisions. Select a replacement for an inherited
assignment: inspect the owning folder and scope explanation before **Confirm
Replacement**. Descendants inherit except nearer overrides, opt-outs, and separately
bound roots; other explicit references to the old source are unchanged. Discarding
the replacement must not save anything. A confirmed repair must survive cancelling
creation, destination failure, and relaunch. A failed settings save must retain the
old choice and report failure, not claim a repair was saved.

Check empty-once destination failure followed by Retry: only this pending creation
stays empty, with safe collision handling and cleanup. The next separate New File
must use its configured source again. Change the destination/binding/effective owner
while recovery is open: review updated details with the name preserved before any
creation or repair. Successful publication must dismiss the sheet before opening
exactly once, focused at the UTF-16 content end, without preview/another rename.
An opening failure must preserve the published file without another creation attempt.
Also recheck Create Template/Edit Template handoff and ordinary untemplated creation.
Package integration tests cover Core results and persisted bytes, not these native
picker, action-label, scope-confirmation, name-preservation, or focus interactions.

### Recoverable same-root rename and drag/move

Native rename, drag/drop, selected-document following, and restart/repair acceptance
remain **UNVERIFIED**. Both sidebar routes use the Core Workspace lifecycle coordinator;
package tests exercise real folders and isolated stores, not native gestures or alerts.
Rename and drag a configured subtree with descendant overrides/opt-outs and a source
used by several folders (including another binding in the same project). Check that
explicit choices follow, inherited content follows the new destination, every source
reference follows, and existing document/source bytes stay unchanged. Check open
documents inside the subtree still save at their actual new paths.

Check destination-record conflicts, occupied filesystem destinations (including case
aliases), case-only source renames, failed intent saves, filesystem failures, and
failed final saves separately. A successful filesystem move with failed final save
must still follow the open document while reporting pending project changes. Restart
before and after the move; only the observable original item at exactly one recorded
location with unchanged root/parent identities may reconcile. Replaced items/parents,
both locations occupied, or unavailable root access must retain the record and choices.
The sidebar retains the recorded paths and **Retry Reconciliation** / **Show in Finder**.
Manually restore the original item to an unambiguous recorded location, restore store
access, then retry; retry never moves, reverses, or discards files. Verify conflicting
assignment/source/binding operations remain blocked while unrelated name/theme edits
remain available. Configured cross-root moves, root relocation, unbind, and trash
policies are not implemented by this slice; unsupported destructive operations fail
closed rather than silently dropping configuration. The full feature is not shipped.
User-facing configured regrant accepts only an observable same-root identity in this
slice. Authoritative library bookmark updates remain allowed without conflicting
pending intent; creation must still revalidate them rather than writing through stale access.
Core rechecks the original item/root/parent identities before returning an editor handoff,
including moves with no configuration changes. Identity rejection retains pending intent
without retargeting a dirty document to a replacement. Verified movement still hands off
when final settings persistence fails, or when filesystem I/O throws after an observable
verified move. No operation is replayed or reversed.

Pending intent reserves its affected assignments' before/after owners, not only spatial
paths. Check a pending source move followed by an owner rename/drag and the reverse:
the second operation must leave disk and settings untouched. Independent choices can move.
Missing destination records use read-only volume case capability and canonical Unicode
comparison; unknown capability blocks ambiguous aliases without changing saved references.

Fresh and stale creation plans must block source-dependent reads and publication while
the effective supplying choice/source is reserved. Explicit **Create Empty Once** can
proceed only through a valid independent destination/owner context without reading that
source. Unrelated untemplated creation remains available; neither bypass changes assignments.

Genuinely unconfigured cross-volume moves between distinct roots retain an explicit
legacy result/route, not the identity-verified handoff contract. Source/destination choices,
descendants, source references, aliases and pending reservations block legacy admission.
Same-root moves never fall back to legacy; unsupported identity-preserving semantics fail
before mutation. Native acceptance of these distinctions is still **UNVERIFIED**.

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`, on the `xcode-27` GitHub-hosted runner (or the runner named by the `MACOS_RUNNER` repository variable). It runs the same checks: `swift test` in each package, both app builds, both linters, and the DMG layout test (in the Lint job). Pushes to `main` also run the release-mode parse speed tests in `GrimoireCore`. A newer push to the same ref cancels the run in progress.

`.github/workflows/release.yml` packages a DMG when a `v*` tag is pushed; see the README.
