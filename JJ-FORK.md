# This is a jj fork of Superpowers

Upstream ([obra/superpowers](https://github.com/obra/superpowers)) drives version
control with git. This fork drives it with [Jujutsu](https://github.com/jj-vcs/jj).

Everything else tracks upstream. Skill names, file names, and the `superpowers:`
namespace are deliberately unchanged, because skills reference each other by
hard-coded name (`superpowers:using-git-worktrees` appears in `executing-plans`,
`writing-plans`, and `subagent-driven-development`) and because renames are the
worst case for a rebase.

## Why a fork rather than local overrides

A same-named personal skill does not shadow a plugin skill — Claude Code
namespaces them apart specifically to avoid collisions — so an override would
sit alongside the git version and never be reached from the cross-references
that matter. Replacing the plugin under its own name is what redirects those
call paths.

## What diverges

| File | Change |
|---|---|
| `skills/using-git-worktrees/` | `jj workspace` instead of `git worktree`; sibling placement by default |
| `skills/finishing-a-development-branch/` | fetch/rebase/bookmark instead of checkout/pull/merge/branch; proactive cleanup guard |
| `skills/requesting-code-review/` | revsets instead of SHAs; `jj diff --from/--to` |
| `skills/subagent-driven-development/scripts/` | `jj root`, `jj log -r BASE..HEAD`, `jj diff` |
| `skills/writing-plans/` | plan template commits with `jj commit` (no staging step) |
| `skills/using-superpowers/references/codex-tools.md` | jj environment detection |

Three git concepts have no jj counterpart and were removed rather than
translated: the submodule guard (jj has no submodules), the detached-HEAD menu
(every jj change is a first-class commit), and the `MAIN_ROOT` directory dance
(jj addresses the repo, not a checked-out tree).

## Configurable document locations

Upstream hardcodes `docs/superpowers/plans/` and `docs/superpowers/specs/`,
noting only in a parenthetical that user preferences override them. This fork
makes that operational with an explicit resolution order:

1. A directory declared in your instructions (CLAUDE.md or project docs)
2. `$SUPERPOWERS_PLANS_DIR` / `$SUPERPOWERS_SPECS_DIR`
3. The upstream default

Instructions rank above the environment variable because they can express
routing a flat value cannot — a destination outside the repository, per-repo
subfolders, naming rules. The variable is for a stable machine-wide default and
is set through the `env` block in Claude Code's `settings.json`.

**Why not the plugin's own `userConfig`.** Claude Code plugins can declare
`userConfig` options in `plugin.json`, settable via `/plugin configure` or
`claude plugin install --config key=value`. Those values reach *hooks* — as
`${user_config.KEY}` or `$CLAUDE_PLUGIN_OPTION_<KEY>` in the hook environment —
and nothing else. A skill is prose an agent reads before running a command, and
the agent's shell does not receive those variables, so `userConfig` cannot carry
configuration into a skill. An ordinary environment variable can.

This is the one divergence in this fork that is not about jj. It is also the
only change to `skills/brainstorming/`, which otherwise tracks upstream exactly.

## Guarding against drift

Upstream adds git commands in ordinary releases — v6.2.0 → v6.3.0 added a
`git status --porcelain` safety guard. A three-way merge only catches such an
addition when it lands next to a line this fork already changed; an addition in
an untouched region merges clean and silently, which is the case worth guarding.

```bash
./tests/claude-code/test-jj-purity.sh          # is this fork still jj-pure?
./tests/claude-code/test-jj-purity.sh --list   # every git command found
```

`.github/workflows/jj-purity.yml` runs that on every push, and weekly diffs
upstream's git-command inventory against `tests/claude-code/jj-purity-upstream-baseline.txt`
so genuinely new commands surface *before* the next rebase rather than after.

The check scans only runnable contexts — fenced shell blocks and shell scripts.
Prose that discusses git as the subject of a worked example is out of scope; see
`tests/claude-code/jj-purity-allowlist.txt`.

## Version scheme and picking up edits

This fork versions as `<upstream-version>-jj.<n>` — `6.3.0-jj.1` sits on upstream
v6.3.0. The suffix is not cosmetic: `claude plugin update` compares the version
in `plugin.json` and skips re-copying when it is unchanged, so editing a skill
has no effect on the installed copy until the version moves. Bump `-jj.<n>` when
you want changes picked up, and reset it on a new upstream base.

Claude Code compares versions by inequality rather than semver precedence, so
the prerelease suffix updating "from 6.3.0 to 6.3.0-jj.1" is accepted even
though semver ranks a prerelease lower.

```bash
# after editing, with plugin.json + marketplace.json bumped:
claude plugin marketplace update superpowers-dev
claude plugin update superpowers          # restart to apply
```

`claude plugin tag` creates a `superpowers--v<version>` git tag from that same
field. The tag is a release marker derived from the version; it is not what
drives an update.

## Taking a new upstream release

```bash
jj git fetch --remote upstream
jj rebase -d <upstream-tag>
./tests/claude-code/test-jj-purity.sh
# then refresh the baseline once any new commands are handled:
./tests/claude-code/test-jj-purity.sh --signature --tree <upstream-checkout> \
  > tests/claude-code/jj-purity-upstream-baseline.txt
```

Rebasing rather than merging is deliberate: it replays the conversion
change-by-change, so a conflict points at the specific rewrite it broke instead
of arriving as one undifferentiated blob.

## Using this fork

```bash
claude plugin uninstall superpowers          # remove the upstream plugin first --
claude plugin marketplace add <path-to-this-repo>   # only one plugin may claim
claude plugin install superpowers            # the `superpowers:` namespace
```
