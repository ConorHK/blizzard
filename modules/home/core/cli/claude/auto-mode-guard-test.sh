#!/usr/bin/env bash
# Regression suite for claude-auto-mode-guard. Feeds crafted PreToolUse payloads
# to the guard binary and asserts each is DENIED (non-empty deny-decision JSON)
# or DEFERRED (no output, exit 0). Wired into `nix flake check` so a future edit
# that reintroduces a slip-through or a false positive fails the build.
#
# Usage: auto-mode-guard-test.sh <path-to-claude-auto-mode-guard>
# Requires jq and git on PATH. Self-contained — seeds its own throwaway repos.
set -uo pipefail

GUARD="${1:?usage: auto-mode-guard-test.sh <guard-binary>}"

# Seed two repos via plumbing (commit-tree/update-ref) so no `git commit` runs —
# the guard would block an unborn-branch commit, and this keeps the suite usable
# even when the guard is active in the surrounding environment.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
seed() { # dir branch
  git init -q "$1"
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
  local tree commit
  tree=$(git -C "$1" write-tree)
  commit=$(git -C "$1" commit-tree "$tree" -m init)
  git -C "$1" update-ref "refs/heads/$2" "$commit"
  git -C "$1" symbolic-ref HEAD "refs/heads/$2"
}
AI="$TMP/ai_repo"
PLAIN="$TMP/plain_repo"
seed "$AI" ai-feature
seed "$PLAIN" main

pass=0
fail=0

# run <deny|defer> <name> <json-payload>
run() {
  local expect="$1" name="$2" json="$3" out decision
  out=$(printf '%s' "$json" | "$GUARD" 2>/dev/null)
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    decision=deny
  elif [ -z "$out" ]; then
    decision=defer
  else
    decision="other:$out"
  fi
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    printf 'ok   [%s] %s\n' "$expect" "$name"
  else
    fail=$((fail + 1))
    printf 'FAIL [want %s got %s] %s\n     out=%s\n' "$expect" "$decision" "$name" "$out"
  fi
}

bash_auto() { jq -nc --arg c "$1" --arg w "$2" \
  '{permission_mode:"auto", tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'; }
bash_mode() { jq -nc --arg m "$1" --arg c "$2" --arg w "$3" \
  '{permission_mode:$m, tool_name:"Bash", tool_input:{command:$c}, cwd:$w}'; }

echo "=== git push / send-pack (deny) ==="
run deny  "git push"                  "$(bash_auto 'git push' "$PLAIN")"
run deny  "git push origin ai-x"      "$(bash_auto 'git push origin ai-feature' "$AI")"
run deny  "git push --force"          "$(bash_auto 'git push --force origin HEAD' "$AI")"
run deny  "git -C repo push"          "$(bash_auto "git -C $AI push" "$PLAIN")"
run deny  "git --no-pager push"       "$(bash_auto 'git --no-pager push' "$AI")"
run deny  "git -c k=v push"           "$(bash_auto 'git -c user.name=x push' "$AI")"
run deny  "sudo git push"             "$(bash_auto 'sudo git push' "$AI")"
run deny  "extra spaces git  push"    "$(bash_auto 'git    push' "$AI")"
run deny  "cd repo && git push"       "$(bash_auto "cd $AI && git push" "$PLAIN")"
run deny  "git fetch && git push"     "$(bash_auto 'git fetch && git push' "$AI")"
run deny  "git send-pack (plumbing)"  "$(bash_auto 'git send-pack origin' "$AI")"

echo "=== git commit (ai-* only) ==="
run defer "commit on ai-*"            "$(bash_auto 'git commit -m x' "$AI")"
run deny  "commit on main"            "$(bash_auto 'git commit -m x' "$PLAIN")"
run defer "commit -C ai-* from plain" "$(bash_auto "git -C $AI commit -m x" "$PLAIN")"
run defer "commit-graph not a commit" "$(bash_auto 'git commit-graph write' "$PLAIN")"

echo "=== interactive modes unaffected (defer) ==="
run defer "default mode git push"     "$(bash_mode default 'git push' "$PLAIN")"
run defer "plan mode git push"        "$(bash_mode plan 'git push' "$PLAIN")"
run defer "acceptEdits git commit"    "$(bash_mode acceptEdits 'git commit -m x' "$PLAIN")"

echo "=== benign / fail-open (defer) ==="
run defer "ls"                        "$(bash_auto 'ls -la' "$AI")"
run defer "git status"                "$(bash_auto 'git status' "$AI")"
run defer "git log --grep commit"     "$(bash_auto 'git log --grep commit' "$AI")"
run defer "echo mentions git push"    "$(bash_auto 'echo running git push later' "$AI")"
run defer "empty payload"             ''
run defer "no permission_mode"        '{"tool_name":"Bash","tool_input":{"command":"git push"}}'

echo
echo "==================================="
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
