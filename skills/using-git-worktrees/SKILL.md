---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or a jj workspace fallback
---

# Using Isolated Workspaces

## Overview

Ensure work happens in an isolated workspace. Prefer your platform's native
workspace tools. Fall back to creating a jj workspace by hand only when no
native tool is available.

**Core principle:** Detect existing isolation first. Then use native tools. Then
fall back to `jj workspace add`. Never fight the harness.

**This repository uses Jujutsu (jj).** Do not run `git` commands. In a
jj workspace there is no `.git` directory at all, so git does not fail
informatively — it reports "not a git repository" and any shell variable you
captured from it is silently empty.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Step 0: Detect Existing Isolation

**Before creating anything, check if you are already in an isolated workspace.**

```bash
ROOT=$(jj root)
WORKSPACE=$(jj workspace list | awk '$2=="." {sub(/:$/,"",$1); print $1}')
```

`jj workspace list` marks the workspace you are standing in with `.` as its
path, so `$WORKSPACE` is the name of the current workspace.

**If `$WORKSPACE` is not `default`:** You are already in a secondary workspace.
Skip to Step 2 (Project Setup). Do NOT create another workspace.

Report with change state:

```
Already in isolated workspace '<name>' at <root>.
```

**If `$WORKSPACE` is `default`:** You are in the primary workspace.

Has the user already indicated their workspace preference in your instructions?
If not, ask for consent before creating one:

> "Would you like me to set up an isolated workspace? It keeps this work off your current working copy."

Honor any existing declared preference without asking. If the user declines
consent, work in place and skip to Step 2.

**No submodule guard is needed.** jj has no submodules, so the ambiguity that
forces one in git does not arise. `jj workspace list` is unambiguous.

**No detached-HEAD case exists either.** Every jj change is a first-class
commit that needs no bookmark to hold it, so there is no degraded state to
detect here and no branch to create up front. Which bookmark should point at
the finished work is a question for finish time, not setup time.

## Step 1: Create Isolated Workspace

**You have two mechanisms. Try them in this order.**

### 1a. Native Workspace Tools (preferred)

The user has asked for an isolated workspace (Step 0 consent). Do you already
have a way to create one? It might be a tool with a name like `EnterWorktree`,
`WorktreeCreate`, a `/worktree` command, or a `--worktree` flag. If you do, use
it and skip to Step 2.

Native tools handle directory placement, change creation, and cleanup
automatically. Running `jj workspace add` when you have a native tool creates
phantom state your harness can't see or manage — and on a harness that
translates its worktree hooks to jj, it also bypasses the placement policy that
keeps workspaces out of the repository.

Only proceed to Step 1b if you have no native workspace tool available.

### 1b. jj Workspace Fallback

**Only use this if Step 1a does not apply** — you have no native workspace tool.

#### Directory Selection

Follow this priority order. Explicit user preference always beats observed
filesystem state.

1. **Check your instructions for a declared workspace directory preference.**
   If the user has already specified one, use it without asking.

2. **Check for an existing project-local workspace directory:**
   ```bash
   ls -d .worktrees 2>/dev/null     # Preferred (hidden)
   ls -d worktrees 2>/dev/null      # Alternative
   ```
   If found, use it. If both exist, `.worktrees` wins.

3. **If there is no other guidance available**, default to a **sibling of the
   repository**: `../<repo-name>-<workspace-name>`.

The sibling default is deliberate and is where jj differs from git. jj snapshots
the working copy automatically on every command — there is no staging step to
forget. A workspace nested inside the repository is therefore absorbed into the
primary workspace's next snapshot unless it is ignored, and unlike git that
happens with no `add` on anyone's part. Placing workspaces outside the
repository removes the hazard rather than managing it.

#### Safety Verification (project-local directories only)

**Only needed if steps 1 or 2 above chose a directory inside the repository.**
A sibling directory needs no ignore rule.

```bash
grep -qE '^\.?worktrees/?$' .gitignore
```

jj honors `.gitignore`, so this is the check either way.

**If NOT ignored:** Add it to `.gitignore` and describe that change before
creating the workspace.

**Why critical:** an unignored nested workspace is swallowed by the parent
workspace's automatic snapshot.

#### Create the Workspace

```bash
name="<workspace-name>"
path="$LOCATION/$name"

jj workspace add --name "$name" "$path"
cd "$path"
```

`jj workspace add` creates the workspace with a fresh empty change on top of the
current workspace's parent. Do **not** follow it with `jj new` — that stacks a
second empty change for no reason.

**Sandbox fallback:** If `jj workspace add` fails with a permission error
(sandbox denial), tell the user the sandbox blocked workspace creation and
you're working in the current directory instead. Then run setup and baseline
tests in place.

## Step 2: Project Setup

Auto-detect and run appropriate setup:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

## Step 3: Verify Clean Baseline

Run tests to ensure workspace starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate.

**If tests pass:** Report ready.

### Report

```
Workspace ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| `jj workspace list` marks a non-`default` workspace | Skip creation (Step 0) |
| Native workspace tool available | Use it (Step 1a) |
| No native tool | `jj workspace add` fallback (Step 1b) |
| `.worktrees/` exists | Use it (verify ignored) |
| `worktrees/` exists | Use it (verify ignored) |
| Both exist | Use `.worktrees/` |
| Neither exists | Check instruction file, then default to a sibling directory |
| Nested directory not ignored | Add to `.gitignore` before creating |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'm obviously not in a workspace — no need to check" | Run Step 0. Harness-created isolation fools eyeballing; `jj workspace list` settles it. |
| "`jj workspace add` is quicker than hunting for a native tool" | A native tool (e.g. `EnterWorktree`) owns placement, change creation, and cleanup. Bypassing it is the #1 mistake — it creates phantom state your harness can't see or manage. |
| "git commands still work, this repo has a `.git`" | Only in the primary workspace of a colocated repo, and even there `git branch --show-current` is empty because jj keeps git detached. A secondary workspace has no `.git` at all, so git reports "not a git repository" and every variable you captured from it is empty — which reads as a passing check, not a failing one. |
| "The workspace directory is surely ignored already" | Check before creating. jj snapshots automatically, so an unignored nested workspace is absorbed with no `add` on anyone's part. |
| "Any directory name works" | Explicit instructions beat an existing project-local directory, which beats the sibling default. |
| "The workspace is fresh — baseline tests can wait" | A dirty baseline makes every later failure ambiguous. Run the tests now; proceeding past failures is your human partner's call. |
