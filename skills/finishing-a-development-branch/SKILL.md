---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work
---

# Finishing a Development Branch

## Overview

**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Clean up.

**This repository uses Jujutsu (jj).** Do not run `git` commands. Work is
carried by changes and bookmarks, not by a checked-out branch.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## Step 1: Verify Tests

Run the project's full test suite (`npm test` / `cargo test` / `pytest` / `go test ./...`).

**If tests fail**, report the failures and stop — the menu comes after a green suite:

```
Tests failing (<N> failures). Must fix before completing:

[Show failures]
```

**If tests pass:** continue to Step 2.

## Step 2: Detect Environment

```bash
ROOT=$(jj root)
WORKSPACE=$(jj workspace list | awk '$2=="." {sub(/:$/,"",$1); print $1}')
```

`jj workspace list` marks the workspace you are standing in with `.`, so
`$WORKSPACE` names it. Capture `$ROOT` now — Step 6 needs it after the
workspace is forgotten.

| State | Menu | Cleanup |
|-------|------|---------|
| `$WORKSPACE` is `default` | Standard 3 options | No workspace to clean up |
| `$WORKSPACE` is anything else | Standard 3 options | Provenance-based (see Step 6) |

There is no reduced menu. git needs one because a detached HEAD cannot hold
work without first creating a branch; in jj every change is a first-class
commit, so all three options are always available.

**No directory dance is needed anywhere in this skill.** jj commands address
the repository, not a checked-out working tree, so integration runs from
wherever you are.

## Step 3: Determine Base Bookmark

The base is whatever this work forked from — usually named in the plan, the
conversation, or the bookmark the work was started against. If it is not
already known, ask: "This work split from <your best guess> - is that correct?"
Confirm before integrating: moving the wrong bookmark is expensive to undo.

## Step 4: Present Options

**Present exactly these 3 options:**

```
Implementation complete. What would you like to do?

1. Integrate into <base-bookmark> locally
2. Push and create a Pull Request
3. Keep as-is (I'll handle it later)

Which option?
```

Present the menu exactly as written — concise, with every option coming
from the list above. Discarding the work happens only in response to your
human partner explicitly asking for it (see "If your human partner asks to
discard the work" below). Wait for their answer; the integration decision
is theirs.

## Step 5: Execute Choice

### Option 1: Integrate Locally

```bash
# Bring the base up to date, then replay the work on top of it
jj git fetch
jj rebase -d <base-bookmark>

# Verify tests on the integrated result
<test command>
```

If tests fail on the rebased result: stop, leave the work and the workspace in
place, and investigate. Nothing has been pushed and nothing has been discarded —
`jj op log` holds the operation, so `jj op restore` returns you to the state
before the rebase if you want to start over.

Once the rebased result is green, move the base bookmark onto it:

```bash
jj bookmark set <base-bookmark> -r <work-head>
```

Then clean up the workspace (Step 6). If the work carried a bookmark of its
own, delete it — otherwise there is nothing to delete, since jj work does not
require a bookmark to exist:

```bash
jj bookmark delete <feature-bookmark>   # only if one was created
```

### Option 2: Push and Create PR

```bash
# If the work has no bookmark yet, push by change ID and let jj name one:
jj git push --change <work-head>

# If it already has a bookmark:
jj git push --bookmark <feature-bookmark>
```

Then create the pull/merge request against the base with the forge's tooling —
its CLI if one is available, or the creation URL most forges print when you
push — following the repo's PR template and conventions if present, and report
the URL to your human partner.

Keep the workspace — your human partner iterates on PR feedback there.

### Option 3: Keep As-Is

Report: "Keeping the work as-is. Workspace preserved at <path>."

### If your human partner asks to discard the work

This path exists only as a response to an explicit request to throw the
work away. Confirm first:

```
This will abandon:
- All changes: <change-list>
- Workspace at <path>

Type 'discard' to confirm.
```

Wait for that exact confirmation. When it arrives:

```bash
jj abandon -r <work-revset>
jj bookmark delete <feature-bookmark>   # only if one was created
```

Then clean up the workspace (Step 6).

Abandoning is recorded in `jj op log` and can be undone with `jj op restore`
while that entry is retained. Say so if asked, but do not treat it as licence
to skip the confirmation: recovery depends on someone noticing in time.

## Step 6: Cleanup Workspace

**Runs for Option 1 and confirmed discards.** Options 2 and 3 always preserve
the workspace.

**If `$WORKSPACE` is `default`:** Primary workspace, nothing to clean up. Done.

**If we created this workspace** — it sits under `.worktrees/`, `worktrees/`,
or the sibling path this project's setup skill chose — we own cleanup.

**First, record what the workspace is holding.** jj will not stop you:

```bash
jj log --no-graph -r '<workspace-name>@' \
  -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
```

This is the step that replaces git's refusal-to-remove guard, and it is
required rather than conditional. `git worktree remove` refuses when the
worktree holds uncommitted files, which makes the danger announce itself.
`jj workspace forget` never refuses: jj has already snapshotted the working
copy into that workspace's `@`, so there is nothing uncommitted to object to.
The change survives the forget and stays in the repo — but no message says so,
and its change ID is about to become the only handle anyone has on it. Report
that ID to your human partner.

```bash
jj workspace forget <workspace-name>
rm -rf "<workspace-path>"
```

`jj workspace forget` detaches the workspace from the repo; it does not delete
the directory, and it does not delete the work.

**Otherwise:** The host environment owns this workspace — leave it in
place. If your platform provides a workspace-exit tool, use it.

## Quick Reference

| Option | Integrate | Push | Keep Workspace | Cleanup Bookmark |
|--------|-----------|------|----------------|------------------|
| 1. Integrate locally | yes | - | - | yes (if one exists) |
| 2. Create PR | - | yes | yes | - |
| 3. Keep as-is | - | - | yes | - |
| Discard (explicit request only) | - | - | - | yes |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests passed earlier this session" | Run the suite on the tree you are about to integrate. A green run only proves the tree it ran on. |
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait. |
| "They seem done with this feature — I'll offer to discard it" | The menu is complete as written. Discard happens only when your human partner asks for it in so many words. |
| "'Yeah, get rid of it' counts as confirmation" | Only the typed word `discard` authorizes it. |
| "The PR is up, so the workspace is clutter now" | PR feedback gets fixed in that workspace. It stays until the work lands. |
| "This other workspace looks stale — I'll clean it too" | Clean up only workspaces this project's setup skill created. Everything else belongs to the host. |
| "`jj workspace forget` succeeded, so nothing was left behind" | It always succeeds — that is the problem. The workspace's `@` change is still in the repo and nothing printed its ID. Record it before forgetting, not after. |
| "jj can undo anything, so the discard confirmation is a formality" | `jj op restore` only helps someone who notices while the operation log still holds the entry. Get the confirmation. |
| "The rebased-result failure is probably flaky" | A failing result stops everything. The work and workspace stay put while you investigate. |
| "The base is obviously main" | Confirm the fork point or ask. Moving the wrong bookmark is expensive to undo. |
| "The push was rejected — force-push will fix it" | A rejected push means the remote moved. Investigate; force-push only on your human partner's explicit request. |
| "There's no bookmark, so there's nothing to push" | jj pushes changes without bookmarks: `jj git push --change <rev>` creates one. Absence of a bookmark is not absence of work. |
