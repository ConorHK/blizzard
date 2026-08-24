# shellcheck shell=bash
# Claude Code PreToolUse guard for Bash tool calls in AUTO permission mode.
#
# Deny-only: emits a `deny` permission decision for the hard guardrails below,
# and otherwise produces NO output (exit 0). A silent exit 0 defers to the
# normal permission flow, so every built-in auto-mode safety rule still applies
# — this hook can only subtract permission, never grant it.
#
# Guardrails (enforced ONLY when permission_mode == "auto"):
#   1. git push is denied outright (send-pack too, the plumbing equivalent).
#   2. git commit (incl. --amend) is allowed only on an `ai-*` branch.
#
# Failure posture:
#   - Cannot confirm auto mode (bad/empty payload, missing field) -> fail-OPEN
#     (defer; the built-in flow still guards the action).
#   - Confirmed auto-mode git commit but branch unresolvable -> fail-CLOSED
#     (deny; a hard guardrail must not pass a commit it cannot verify).
#   - git push is an UNCONDITIONAL denial, so there is no value to verify and
#     thus no fail-closed branch: detection -> deny, and non-detection defers
#     (fail open) like the other heuristics below.
#
# This is a heuristic, not a real shell parser. Known accepted limitations (all
# fail SAFE — they deny or defer, never grant a commit/push that should be
# blocked): surrounding quotes are stripped per segment before tokenizing, so a
# separator (`;`/`&&`/`|`) inside a quoted `-m` message splits the command (the
# real segment is still matched); `cd`/`-C` are followed only as literal leading
# tokens; and indirection the parser can't see (`eval`, `bash -c`, `g=git;$g
# push`, backslash-escaped names) is not resolved. These edges fail safe for
# normal interactive usage.
#
# Runs under `set -euo pipefail` (writeShellApplication); jq and git are pinned
# on PATH via runtimeInputs.

# Emit a deny decision (reason is JSON-encoded by jq) and stop.
deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

input=$(cat)

# Fail-open if the payload is empty or unparseable, or if we are not in auto mode.
pm=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null) || exit 0
[ "$pm" = "auto" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""

# Detect a simple command that invokes `git`, find its real subcommand, and
# report it via SEG_GIT_SUBCMD (also capturing `-C <path>` into SEG_GIT_C).
# Walks past env-assignment prefixes, command wrappers, the program name, and
# git global options (incl. value-taking ones like `-C <path>`) to find the
# subcommand — so `git -C /p commit` and `git push` match while `git commit-graph`
# and `git log --grep commit` resolve to those literal first subcommand tokens
# (`commit-graph`, `log`), which the loop ignores.
SEG_GIT_C=""
SEG_GIT_SUBCMD=""
segment_is_git() {
  local seg="$1"
  SEG_GIT_C=""
  SEG_GIT_SUBCMD=""
  local -a toks
  read -ra toks <<< "$seg"
  local n=${#toks[@]}
  local i=0
  [ "$n" -gt 0 ] || return 1

  # Skip leading env assignments and command wrappers.
  while [ "$i" -lt "$n" ]; do
    case "${toks[i]}" in
      *=*) i=$((i + 1)) ;;
      command | exec | builtin | sudo) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1

  # Program must be git (allow an absolute path like /usr/bin/git).
  case "${toks[i]##*/}" in
    git) ;;
    *) return 1 ;;
  esac
  i=$((i + 1))

  # Skip git global options; the value-taking ones consume the next token.
  # Capture -C's value so the branch is checked in the repo git will act on.
  while [ "$i" -lt "$n" ]; do
    case "${toks[i]}" in
      -C)
        SEG_GIT_C="${toks[i + 1]:-}"
        i=$((i + 2))
        ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path | --super-prefix)
        i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || return 1

  SEG_GIT_SUBCMD="${toks[i]}"
}

# Join a (possibly relative) directory onto the running effective cwd.
join_dir() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$2" "$1" ;;
  esac
}

# Split the command into simple-command segments on shell separators so each
# `git ...` invocation is inspected independently. Every separator is tagged so
# each segment knows both the operator that PRECEDES it and the one that
# FOLLOWS it. A leading `cd <dir>` is honored ONLY when the shell is guaranteed
# to run it in the parent shell: reached sequentially (start or `;`) AND
# terminated sequentially (`;`, `&&`, `||`, or end). A `cd` that is conditional
# (`false && cd`, `true || cd`), in a pipe or background subshell (`cd x | …`,
# `cd x &`), or wrapped in `( … )` is NOT honored — the real shell may skip it
# or run it in a subshell — so it taints the effective dir, and a matched git
# commit then fails CLOSED (deny). This keeps the common `cd repo && git commit`
# working while refusing to *grant* permission off a `cd` the shell would not
# actually apply to the parent.
effective_cwd="$cwd"
commit_dir=""
is_git_commit=0
cd_tainted=0

# A literal newline is a sequential separator like `;`, so fold newlines to `;`
# first — this lets a multi-line `cd repo` / `git commit` script honor the cd
# instead of failing closed on the line break. Then tag each separator distinctly
# (order matters: && and || before & and |).
norm=$(printf '%s' "$cmd" | tr '\n' ';' | sed -E '
  s/\&\&/\n@@AND@@ /g
  s/\|\|/\n@@OR@@ /g
  s/;/\n@@SEMI@@ /g
  s/\|/\n@@PIPE@@ /g
  s/&/\n@@AMP@@ /g')

# Collect segments with the separator that precedes each (PRESEP[0] = START).
declare -a SEGS PRESEP
n_seg=0
while IFS= read -r rawseg; do
  case "$rawseg" in
    "@@AND@@ "*) ps=AND; s=${rawseg#@@AND@@ } ;;
    "@@OR@@ "*) ps=OR; s=${rawseg#@@OR@@ } ;;
    "@@SEMI@@ "*) ps=SEMI; s=${rawseg#@@SEMI@@ } ;;
    "@@PIPE@@ "*) ps=PIPE; s=${rawseg#@@PIPE@@ } ;;
    "@@AMP@@ "*) ps=AMP; s=${rawseg#@@AMP@@ } ;;
    *) ps=START; s="$rawseg" ;;
  esac
  SEGS[n_seg]="$s"
  PRESEP[n_seg]="$ps"
  n_seg=$((n_seg + 1))
done <<< "$norm"

k=0
while [ "$k" -lt "$n_seg" ]; do
  seg=$(printf '%s' "${SEGS[k]}" | sed "s/[\"']//g")
  presep="${PRESEP[k]}"
  # Following separator is the next segment's preceding separator (END if last).
  nextsep="${PRESEP[k + 1]:-END}"
  k=$((k + 1))
  [ -n "$seg" ] || continue
  read -ra segtoks <<< "$seg"
  # Detect `cd <dir>`, seeing past a subshell-opening `(` (never honored).
  j=0
  subshell=0
  while [ "$j" -lt "${#segtoks[@]}" ] && [ "${segtoks[j]}" = "(" ]; do
    subshell=1
    j=$((j + 1))
  done
  if [ "${segtoks[j]:-}" = "cd" ] && [ -n "${segtoks[j + 1]:-}" ]; then
    pre_ok=0
    case "$presep" in START | SEMI) pre_ok=1 ;; esac
    next_ok=0
    case "$nextsep" in SEMI | AND | OR | END) next_ok=1 ;; esac
    if [ "$subshell" -eq 0 ] && [ "$pre_ok" -eq 1 ] && [ "$next_ok" -eq 1 ]; then
      effective_cwd=$(join_dir "${segtoks[j + 1]}" "$effective_cwd")
    else
      cd_tainted=1
    fi
    continue
  fi
  if segment_is_git "$seg"; then
    case "$SEG_GIT_SUBCMD" in
      # `send-pack` is the plumbing command that performs the same wire push, so
      # it is denied too; other indirection (eval, bash -c) is not statically
      # visible and falls under the accepted limitations documented at the top.
      push | send-pack)
        deny "Auto mode: git push is not allowed. Stop and let a human push."
        ;;
      commit)
        if [ -n "$SEG_GIT_C" ]; then
          commit_dir=$(join_dir "$SEG_GIT_C" "$effective_cwd")
        else
          commit_dir="$effective_cwd"
        fi
        is_git_commit=1
        break
        ;;
    esac
  fi
done

if [ "$is_git_commit" -eq 1 ]; then
  # An unhonored cd before the commit means we cannot trust the dir: fail closed.
  if [ "$cd_tainted" -eq 1 ]; then
    deny "Auto mode: git commit follows a conditional or subshell 'cd' whose target cannot be verified. Run the commit from an ai-* branch checkout without a conditional/subshell cd."
  fi
  branch=""
  if [ -n "$commit_dir" ]; then
    branch=$(git -C "$commit_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  fi
  case "$branch" in
    ai-*) : ;;
    *)
      deny "Auto mode: git commit is only allowed on an ai-* branch, but the current branch is '${branch:-unknown}'. Create/switch to an ai-<feature> branch first."
      ;;
  esac
fi

exit 0
