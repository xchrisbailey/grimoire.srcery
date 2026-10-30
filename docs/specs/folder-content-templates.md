# Folder content templates

Status: decisions complete; ready for implementation planning. No feature implementation is included.

This is the canonical implementation spec. The completed [Folder content templates map](https://github.com/xchrisbailey/grimoire.srcery/issues/74) and its resolution comments record the decisions and their rationale.

## Problem statement

New documents start empty. A writer creating a blog post must repeatedly insert the same frontmatter and document structure, even though the destination folder identifies the kind of document being written. Existing filename patterns and manual frontmatter insertion do not supply folder-specific initial content.

## Solution

Let a user assign an ordinary Markdown file as a folder's content template. New documents created in that folder or its descendants start from the source's saved contents, with simple placeholders expanded for the actual initial filename and creation time.

Assignments belong to a project. The nearest explicit folder choice wins within the most-specific bound root. Users can override inheritance or explicitly disable templates. Sources remain ordinary editable files, reusable by multiple assignments.

### Shipping prerequisite

Fix [A projects.json that fails to load is overwritten with an empty library](https://github.com/xchrisbailey/grimoire.srcery/issues/68) before shipping. It remains open as of this spec's assembly.

Failed project loads must preserve the existing file. Assignment changes also require observable save failures and staged commits; they must not appear successfully saved when persistence fails. These requirements are part of the implementation contract, not claims that storage has already been fixed.

## Scope

- Apply templates only to new documents created through Grimoire's Mac menu, shortcut, command palette, or folder context menu.
- Include folder assignment, inheritance, opt-out, template authoring, simple placeholders, safe creation, recovery, and assignment/source lifecycle handling.
- Keep Core logic platform-neutral and both apps building. The current iOS app has no creation UI; adding one is outside this effort.
- Keep untemplated creation's existing user experience.

Out of scope:

- General folder automation, scripts, expressions, custom placeholder definitions, and custom date-format languages.
- Applying templates to existing, imported, synced, or externally created documents; ongoing frontmatter/schema enforcement.
- Reapplying content when an existing document is renamed or moved.
- Automatic correlation of external descendant-folder/source renames or moves, or reliable detection of external folder replacement while the app is closed.
- Per-placeholder prompts, content previews, a cursor placeholder, smart caret positioning, and automatic YAML parsing or rewriting.
- Portable folder-side configuration files or automatic assignment transfer to another computer.

Use the terms in [GLOSSARY.md](../../GLOSSARY.md), particularly content template, content placeholder, template source, filename pattern, folder template assignment, template opt-out, and unresolved folder template assignment.

## Authoring and assignment

A template source is an ordinary Markdown file inside any folder bound to the active project. A dedicated templates folder is allowed. Assignments reference the source rather than copying a snapshot.

The folder context menu offers `Content Template…` with these choices:

| Choice | Meaning |
| --- | --- |
| Inherit | Remove the folder's explicit choice and continue ancestor lookup. |
| Use a template | Select an explicit source, replacing inherited content rather than merging it. |
| No template | Explicitly disable inherited templates for the folder and descendants until a deeper override. |

Configuration shows the effective template and the folder it was inherited from. `Use a template` offers `Choose Existing File…` and `Create Template…`. `Edit Template` opens the source as an ordinary document.

`Create Template…` asks where to save a Markdown file within the active project's bound folders, creates it empty without applying a content template, and opens it for editing. Assign it only after source creation succeeds and the assignment is persisted. Cancellation or failed source creation leaves the previous assignment unchanged. A settings-save failure must be reported, not shown as a completed assignment.

Saving a source changes future documents using it. Existing documents never change. An open source's unsaved editor buffer does not supply template content.

Sources and assignments have different ownership: copying a folder carries its Markdown sources, but assignments stay in Grimoire's project settings.

## Matching

1. Resolve the actual destination folder using the creation command's existing rules. Do not match against an unrelated current selection.
2. Consider only the active project's assignments and bound roots.
3. Select the most-specific bound root containing the destination. Equivalent-depth aliases use project order as a deterministic tie-break.
4. Inspect the destination and then its ancestors, stopping at that root. Never search beyond it or fall back to an outer overlapping binding.
5. Use the nearest active explicit choice. `Use a template` selects its source; `No template` selects empty content. A deeper choice can override either.
6. If no active explicit choice exists, use today's empty-file creation behavior.

A broken source is still an explicit choice and must enter recovery. It is not permission to continue ancestor lookup. An unresolved folder template assignment is inactive and requires explicit relinking or removal.

Examples:

- With only `blog` bound, `blog/drafts` inherits the blog template unless it has a nearer choice.
- A drafts-specific source replaces the blog source completely.
- `blog/archive` can disable templates, while `blog/archive/special` explicitly selects one again.
- If the project separately binds `blog/drafts`, lookup there starts and stops within that narrower root. Without its own applicable choice, creation is empty even when the outer `blog` binding has a template.
- Different projects can assign different sources to the same physical folder.

## New-document experience

When a template applies, resolve matching and show a naming dialog before creating the document. Display the destination and source. Prefill the name from the existing filename pattern, edit only the stem, and display `.md` separately.

Typed names are literal. Reject empty/whitespace-only stems, surrounding whitespace, leading dots, `.` and `..`, path separators, and control characters with a visible explanation. Do not trim, sanitize, prettify, or evaluate typed names as patterns. Allow normal punctuation and Unicode; append `.md` to the literal stem. Generated suggestions retain existing filename-pattern sanitization.

On confirmation:

1. Revalidate the displayed destination, binding, and effective template. If a relevant configuration change occurred in another window, preserve the entered name and ask the user to review updated details before creating anything. Unrelated edits need not force review. Saved edits to the same source remain intentionally live.
2. Capture one creation-attempt timestamp. Regenerate an untouched suggested name from that timestamp; preserve a user-edited name instead.
3. Allocate the actual collision-safe filename and expand the saved source for it.
4. Publish the complete document safely, then open it with editor focus and the caret at the end of its content.

Do not add a preview, another confirmation, or the existing automatic post-creation rename prompt. Authors can end sources with blank lines where writing should begin. Cancellation creates no document; do not create a placeholder file to collect its name. Delay templated-creation directory/file side effects until confirmation.

The same flow applies to all in-scope creation commands after their destination resolution. With no template or an explicit opt-out, retain today's creation flow. `Create Template…` uses its separate empty-source authoring flow.

## Placeholder expansion

| Placeholder | Value |
| --- | --- |
| `{title}` | Initial allocated filename without its extension, including any collision suffix. |
| `{filename}` | Initial allocated filename including its extension and any collision suffix. |
| `{date}` | Local creation date in fixed `YYYY-MM-DD` form, such as `2026-10-30`. |
| `{time}` | Local creation time in fixed 24-hour `HH:mm:ss` form, such as `14:05:09`. |

Preserve title spaces and punctuation without prettifying. `My first post 2.md` supplies title `My first post 2` and filename `My first post 2.md`.

All date/time values in one attempt use the same captured instant, including existing filename patterns. Preserve those patterns' existing `HHmm` time formatting; the content placeholder uses `HH:mm:ss`. An untouched suggested filename refreshes on confirmation or user-visible retry, including across midnight. Once edited, its text remains literal.

Expansion is case-sensitive and single-pass. Never scan inserted values or escaped text again. Later moves or renames do not update content.

### YAML-safe values

Each placeholder also supports a fixed `:yaml` form, such as `{title:yaml}` or `{date:yaml}`. It produces a double-quoted YAML string, with quote, backslash, control-character, and line-break escaping. Date and time values are strings too. Authors use these forms without surrounding quotes.

Ordinary forms insert raw text and do not guarantee valid YAML. Do not infer quoting from surrounding text or parse, validate, restructure, or reserialize the frontmatter.

### Literal text

| Source | Result |
| --- | --- |
| `{{title}}` | Literal `{title}` |
| `{{title:yaml}}` | Literal `{title:yaml}` |
| `{Title}` | Unchanged |
| `{author}` | Unchanged |
| `{title:other}` | Unchanged |
| Unfinished `{title` | Unchanged |

Only the four lowercase names, their exact `:yaml` forms, and doubled-brace escapes receive special treatment. Unknown or incomplete forms are not creation errors. Preserve other text without rewriting it.

### Blog example

Assign a saved source containing:

```markdown
---
title: {title:yaml}
date: {date:yaml}
---

# {title}

```

Creating `My first post.md` on local date October 30, 2026 produces:

```markdown
---
title: "My first post"
date: "2026-10-30"
---

# My first post

```

If that filename is taken, the allocated suffix also appears in the heading and frontmatter title. Open the document at the expanded content's end without another rename prompt.

## Source eligibility and preservation

Read one saved-source snapshot directly from disk per creation attempt. Require a Markdown file containing valid UTF-8 text. Reject NUL-containing binary content and invalid UTF-8 through source recovery; do not use the editor's lossy UTF-8 decoding path. An empty readable source is valid, and unusual or malformed YAML is not a validation failure.

Preserve a UTF-8 BOM, CRLF/LF/lone-CR sequences, whitespace, and final-newline presence outside substitutions and escapes. Write UTF-8 without Markdown/YAML reserialization. Never modify the source during creation.

Resolve symbolic links when checking source containment. The target must be inside some currently accessible folder bound to the active project. A link into an otherwise unbound location is ineligible; bind that folder or choose another source. Do not borrow another project's access or rely on stale last-known root paths.

## Safe file creation

An existence check followed by ordinary file creation is insufficient. The shared creation module must:

1. Choose a candidate using existing `stem.md`, `stem 2.md`, and subsequent suffix conventions.
2. Expand from the saved snapshot using that candidate's actual name.
3. Fully write and close an exclusively owned temporary file in the destination directory.
4. Publish it with a same-directory atomic no-replacement operation, such as an exclusive-rename capability. Do not use replacement-style atomic saving for initial creation.
5. If a competitor claims the candidate, choose the next available suffix, regenerate content for that name from the same snapshot, and retry publication.

Allow at most 32 no-replacement publication attempts per creation attempt. Internal collision retries retain the attempt's timestamp and saved-source snapshot. Exhaustion is a reported failure. A user-visible Retry starts a fresh attempt.

Never expose a partially written final document, overwrite a competing file, or open before publication succeeds. Clean up only temporary artifacts known to belong to this attempt. Unsupported publication semantics, lost access, or changed destination context must produce an error/review result, not an unsafe fallback. Keep access and validated context valid through publication.

`Create Empty Once` uses the same filename and publication protections. A failure to open an already-published document is an open error; do not create another copy or delete the published document as creation rollback.

## Recovery

A missing, inaccessible, unreadable, ineligible, or unsupported-text source stops normal creation. Identify the source and reason, then offer:

| Action | Effect |
| --- | --- |
| Retry | Reread saved source, recheck names, and capture a fresh attempt timestamp. Preserve any typed name. |
| Choose Replacement… | Repair the explicit assignment that supplied this source after confirming its scope. |
| Create Empty Once | Bypass templating for this pending document creation, including retries if its destination write fails. |
| Cancel | Stop creation without producing a document. |

Never silently choose an ancestor's source, substitute cached content, remove an assignment, or create empty content.

For an inherited source, replacement repairs the owning ancestor assignment rather than adding a destination override. Show that folder and explain which descendants inherit the change. Other explicit assignments referencing the old source remain unchanged. Validate the replacement's eligibility and saved text before committing the repair.

A confirmed repair is a separate persisted settings edit. It survives later cancellation or document-write failure. Retry does not otherwise modify assignments. The next separate New File command uses configured templating again after an empty-once exception.

Failed destination writes must preserve existing documents, source files, and assignments, apart from intentional confirmed repairs. Report the error, do not open partial content, and never clean up an unrelated file.

## Assignment and source lifecycle

| Event | Required behavior |
| --- | --- |
| In-app folder rename/move | Carry explicit choices and descendant choices, including across bound roots in the same project. Recompute inherited behavior at the destination. |
| Destination-side assignment conflict | Stop before moving anything; explain the conflict and require resolution without overwriting either configuration. |
| In-app source rename/move | Update all affected source references in the active project while the source remains in its bound folders. |
| Same bound root relocated | Preserve assignments and source references when the bookmark still identifies that root. |
| Access recovery selects a different folder | Require confirmation before carrying configuration over. |
| Add overlapping inner binding | Start it unconfigured. Retain outer records, inactive within the inner lookup boundary; do not copy them. |
| Unbind root | Warn about owned configuration loss, then remove its owned assignments/opt-outs after a successful settings commit. Leave disk files untouched. Rebinding starts unconfigured. |
| Remove inner overlapping binding | Delete its owned records; applicable outer rules become effective again. |
| Trash folder in Grimoire | Warn about its explicit and descendant choices. Remove them only after successful trash; failure preserves them. Restoring from Trash requires reassignment. |
| Detect configured folder missing after external change | Persist an inactive unresolved folder template assignment and offer Locate Folder… or Remove Assignment. |
| Old path reappears after becoming unresolved | Keep the choice inactive until explicitly relinked or removed. |
| Source lost or externally moved | Require explicit relinking/replacement; do not guess the new source. |

Warn before trashing a referenced source or unbinding a folder containing sources used by other bindings. Explain the active project's affected assignments. If the user proceeds, keep assignments owned by remaining bindings as broken references; do not erase them or fall back. Removing the source's own binding still removes records owned by that binding.

External folder deletion follows the unresolved-assignment policy, not automatic removal of configuration. External source deletion/loss of access follows source recovery. Neither rule promises detection of identity changes the current watcher/bookmark system cannot observe while the app is closed.

### Recovery records for filesystem changes

Moves, renames, and trash operations that also change assignments or source references need a durable recovery record before filesystem mutation. Record the operation, relevant source/destination/root identities, intended before/after configuration, and enough observable identity to reconcile safely. Store it in app/project persistence, not hidden files in user folders.

Preflight ownership and conflicts first. Failed preparation leaves the filesystem and configuration untouched. After filesystem success, atomically commit the new configuration and clear the pending record. Failed final persistence remains a pending recoverable operation, not a reported successful configuration save.

On restart, complete reconciliation only when recorded identities and actual state make the outcome unambiguous. Otherwise surface repair and preserve the record/configuration until explicitly resolved. Do not blindly replay destructive operations or reverse moves. Block further conflicting mutations while reconciliation is pending.

## Project persistence

Use additive project-owned assignment records in the existing project envelope. References for owner folders and sources use bound-root UUID plus relative path. Persist explicit use-source/no-template choices and unresolved-folder state; absence of an active choice represents inheritance.

Legacy projects with no assignment field load with empty configuration. Malformed types, invalid modes/references, and conflicting duplicate folder choices produce diagnostics, not silent empty configuration. Preserve the existing file on load failure. Concrete Codable field names remain implementation details.

Validate decoded references as well as URL-constructed ones. Reject absolute/traversing paths; compare resolved path components rather than string prefixes. An empty folder-relative path can refer to the bound root. A source must resolve to an eligible file, not a directory.

Stage settings changes and publish the in-memory snapshot only after successful atomic persistence. Settings-only assignment, replacement, opt-out, and unbind operations use one commit. Report failed saves and release bound-root access only after successful unbind persistence. Serialize relevant in-process mutations across windows to avoid lost updates.

## Module interface and integration

One deep module in `GrimoireCore` owns matching, saved-source loading, expansion, collision handling, temporary output, and publication. The Mac app owns prompts, localized presentation, selection, and focus. Core must not import UI frameworks, and the feature must not introduce a framework, dependency, or YAML parser.

Expose two creation phases:

- Prepare returns destination, effective source/owning assignment, suggested filename, and enough project/root/configuration identity for revalidation. It does not create a placeholder document.
- Create accepts confirmed naming intent and explicit recovery choices, then returns a successfully published URL and editor handoff information, or a structured failure/review-needed result. Callers must not independently sequence allocation, expansion, and writing.

Keep clock/calendar, file-operation failures, and isolated project storage as internal test seams. Add adapters only where production and deterministic tests need different behavior. Test principally through the shared interface, not implementation internals.

Existing integration points:

| Location | Responsibility |
| --- | --- |
| `Apps/GrimoireMac/Window/WindowState.swift` | Global destination resolution, document selection, and editor handoff. |
| `Apps/GrimoireMac/Sidebar/FileActions.swift` | Shared creation actions, current create/rename flow, and lifecycle callbacks. |
| `Apps/GrimoireMac/Sidebar/FileTreeView.swift` | Folder-context creation, assignment entry point, and lifecycle warnings. |
| `Apps/GrimoireMac/Window/GrimoireCommands.swift` and `Apps/GrimoireMac/Palette/Incantations.swift` | Existing menu/shortcut and palette entry points. |
| `Packages/GrimoireCore/Sources/GrimoireCore/Workspace/FileOperations.swift` | Existing naming/allocation and filesystem operations; current creation is not race-safe. |
| `Packages/GrimoireCore/Sources/GrimoireCore/Workspace/FileNaming.swift` | Existing deterministic filename-pattern expansion. |
| `Packages/GrimoireCore/Sources/GrimoireCore/Workspace/Project.swift`, `ProjectLibrary.swift`, and `ProjectStore.swift` | Assignment identities, persistence, and staged/recoverable changes. |
| `Packages/GrimoireCore/Sources/GrimoireCore/Workspace/Workspace.swift` | Bound-root access and reference resolution; template lookup needs most-specific-root selection rather than unrelated first-root behavior. |

Follow [CODING_STANDARDS.md](../../CODING_STANDARDS.md), including String Catalog entries for new user-facing strings and UTF-16 editor caret offsets. Do not broaden this work into an unrelated ownership or storage redesign.

## Testing decisions

Use existing real-temporary-folder fixtures and isolated project stores. Accept deterministic clock/calendar inputs and narrowly controlled filesystem/storage failures so races and interrupted operations can be reproduced. Do not add an app automation framework or dependencies for this feature.

Integration acceptance groups:

- Legacy decode, assignment round-trip, malformed records, failed reads/commits, and preservation of the original project file.
- Nearest-choice matching, inheritance/override/opt-out, overlapping roots, project isolation, deterministic equivalent-root selection, traversal rejection, source symlinks, and unavailable roots.
- Saved rather than unsaved source content, empty sources, invalid UTF-8/NUL rejection, and byte preservation for BOM, line endings, whitespace, and final newline. Sources remain untouched.
- Actual allocated title/filename values, collision suffixes, one local timestamp, midnight refresh versus literal typed names, YAML-safe strings, escapes, unknown/incomplete forms, and no recursive expansion.
- Deterministic competing-creator races, intact competitor bytes, matching inserted filenames, stable within-attempt snapshot/time, the retry limit, safe cleanup, and no partial final publication.
- Read/write/access failures, repair scope and persistence, fresh user-visible Retry, cancel, empty-once retries, and a later separate creation returning to its configured template.
- Folder/source moves and renames, descendant choices, cross-root migration, conflicts, root relocation/regrant, overlapping bindings, unbind/trash, missing/reappearing paths, and interrupted lifecycle reconciliation.
- Relevant configuration changes while naming, with preserved typed input and review before creation.
- Untouched existing/imported/synced/external documents, the Create Template bypass, unchanged untemplated behavior, and open failure after successful publication without duplicate creation.

Focused expansion examples are appropriate; avoid trivial tests of language/library behavior. Existing package fixtures include `WorkspaceTests.swift`, `LooseFileTests.swift`, `OpenDocumentTests.swift`, and round-trip corpora under `Packages/GrimoireCore/Tests/GrimoireCoreTests/`.

Manual Mac acceptance covers each real menu/shortcut, palette, and folder-context route: destination/source display, name validation, cancel, suffix handling, no preview/second rename, focused editor/caret, inherited repair scope, warnings, and recovery dialogs. There is no established automated app test harness.

Implementation must pass the checks in [Development](../development.md): both app builds, all three package test suites, both linters, and the DMG-layout test. Report results under the repo's [orchestration rules](../agents/orchestration.md) and apply the required adversarial review for stored-project, workspace, and saving changes. Implementation and test writing go through the `coder` role; the lead reviews and merges.

## Decision provenance

The spec consolidates the following closed decisions without reopening them:

- [Define folder-template matching and inheritance](https://github.com/xchrisbailey/grimoire.srcery/issues/75)
- [Define how users author and assign folder content templates](https://github.com/xchrisbailey/grimoire.srcery/issues/76)
- [Define placeholder expansion and its relationship to filenames](https://github.com/xchrisbailey/grimoire.srcery/issues/77)
- [Define assignment behavior when folders move or bindings change](https://github.com/xchrisbailey/grimoire.srcery/issues/78)
- [Define template source recovery and creation failure behavior](https://github.com/xchrisbailey/grimoire.srcery/issues/79)
- [Define the new-document experience when applying a content template](https://github.com/xchrisbailey/grimoire.srcery/issues/80)
- [Define folder-template integration contracts and verification](https://github.com/xchrisbailey/grimoire.srcery/issues/81)

No further product or technical decision is currently outstanding. Implementation breakdown and the persistence prerequisite are the next work; this spec does not claim they are complete.
