#!/usr/bin/env bash
# Regression check: this fork replaces git with Jujutsu (jj).
#
# A git command that survives in a skill's *runnable* instructions is a defect:
# it either fails outright (a jj workspace has no .git at all) or silently
# mixes two VCS front-ends against one repo. Upstream adds git commands in
# every release, so this check is what turns a clean merge into a visible one.
#
# Scope is deliberately narrow -- only contexts an agent will actually execute:
#   1. fenced bash/sh/shell blocks in skills/**/*.md
#   2. shell scripts anywhere under skills/
# Narrative prose is NOT scanned. Several skills discuss git as the subject of
# a worked example (systematic-debugging tells a story about `git init` firing
# in the wrong directory); flagging those would make this check permanently red
# for reasons nobody can fix, and a permanently red check gets ignored.
#
# Anything intentionally left as git belongs in jj-purity-allowlist.txt WITH A
# REASON. The allowlist matches on file + command substring rather than line
# number, so an upstream reflow keeps passing while an upstream *edit* to the
# command itself correctly re-opens the question.
#
# Usage:
#   test-jj-purity.sh           # check; non-zero exit on unallowlisted git
#   test-jj-purity.sh --list    # print every git command found, allowlist ignored
#   test-jj-purity.sh --signature  # stable path|command set, for baseline diffing
#   test-jj-purity.sh --tree D  # scan D instead of this repo (for upstream drift checks)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="$SCRIPT_DIR/jj-purity-allowlist.txt"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

mode="check"
while [ $# -gt 0 ]; do
    case "$1" in
        --list) mode="list"; shift ;;
        --signature) mode="signature"; shift ;;
        --tree) REPO_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

SKILLS_DIR="$REPO_ROOT/skills"
[ -d "$SKILLS_DIR" ] || { echo "no skills/ directory under $REPO_ROOT" >&2; exit 2; }

# A git invocation: 'git' as a command word, not part of github/.github/foo-git.
# Each candidate line is probed with a leading space prepended, so the pattern
# needs no '^' alternative -- '^' inside a group is not portable across awks.
GIT_RE='[^A-Za-z0-9_./-]git[[:space:]]+[-A-Za-z]'

# Emit "path:line:text" for git commands inside lang-tagged shell fences.
# Entering requires a language tag; any bare fence closes. That handles the
# nested ````/```bash fences the plan template uses. The git match happens here,
# on the raw line -- filtering the prefixed output instead would let the "path:N:"
# prefix eat the delimiter the pattern needs.
scan_markdown() {
    awk -v re="$GIT_RE" '
        /^[[:space:]]*```+[[:space:]]*(bash|sh|shell|console)[[:space:]]*$/ { infence=1; next }
        /^[[:space:]]*```+[[:space:]]*$/                                    { infence=0; next }
        infence { probe = " " $0; if (probe ~ re) printf "%s:%d:%s\n", FILENAME, FNR, $0 }
    ' "$1"
}

scan_script() {
    awk -v re="$GIT_RE" '
        { probe = " " $0; if (probe ~ re) printf "%s:%d:%s\n", FILENAME, FNR, $0 }
    ' "$1"
}

findings=""
while IFS= read -r f; do
    hit="$(scan_markdown "$f")"
    [ -n "$hit" ] && findings+="$hit"$'\n'
done < <(find "$SKILLS_DIR" -type f -name '*.md' | sort)

while IFS= read -r f; do
    hit="$(scan_script "$f")"
    [ -n "$hit" ] && findings+="$hit"$'\n'
done < <(find "$SKILLS_DIR" -type f \( -name '*.sh' -o -perm -u+x \) ! -name '*.md' | sort)

findings="$(printf '%s' "$findings" | grep -v '^$' || true)"

if [ "$mode" = "signature" ]; then
    # path|command, whitespace-normalised, sorted, deduped, NO line numbers.
    # Line numbers would turn every upstream reflow into fake drift; the command
    # text is what we actually have to convert, so that is what we track.
    printf '%s\n' "$findings" | sed "s|^$REPO_ROOT/||" | awk '
        { match($0, /^[^:]+:[0-9]+:/)
          rel = substr($0, 1, RLENGTH); sub(/:[0-9]+:$/, "", rel)
          cmd = substr($0, RLENGTH + 1)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", cmd); gsub(/[[:space:]]+/, " ", cmd)
          print rel "|" cmd }
    ' | sort -u
    exit 0
fi

if [ "$mode" = "list" ]; then
    if [ -z "$findings" ]; then echo "No git commands found in runnable skill contexts."; exit 0; fi
    printf '%s\n' "$findings" | sed "s|^$REPO_ROOT/||"
    echo
    echo "$(printf '%s\n' "$findings" | wc -l | tr -d ' ') git command line(s) in runnable contexts."
    exit 0
fi

# Allowlist lines: <path>|<command substring>|<reason>   ('#' comments, blanks ok)
allowed() {
    local file="$1" text="$2" path pat reason
    [ -f "$ALLOWLIST" ] || return 1
    while IFS='|' read -r path pat reason; do
        case "$path" in ''|'#'*) continue ;; esac
        [ -n "${reason:-}" ] || continue          # an entry without a reason does not count
        [ "$file" = "$path" ] || continue
        case "$text" in *"$pat"*) return 0 ;; esac
    done < "$ALLOWLIST"
    return 1
}

echo "jj purity check -- git commands in runnable skill contexts"
echo "  tree: $REPO_ROOT"
echo ""

violations=0 permitted=0
while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    file="${finding%%:*}"; rest="${finding#*:}"
    line="${rest%%:*}"; text="${rest#*:}"
    rel="${file#"$REPO_ROOT"/}"
    if allowed "$rel" "$text"; then
        permitted=$((permitted + 1))
    else
        echo "  [FAIL] $rel:$line"
        echo "         ${text#"${text%%[![:space:]]*}"}"
        violations=$((violations + 1))
    fi
done <<< "$findings"

echo ""
if [ "$violations" -eq 0 ]; then
    echo "  [PASS] no unallowlisted git commands ($permitted allowlisted)"
    exit 0
fi
echo "  $violations unallowlisted git command(s); $permitted allowlisted"
echo ""
echo "  Rewrite each in jj terms, or add it to $(basename "$ALLOWLIST") with a reason."
exit 1
