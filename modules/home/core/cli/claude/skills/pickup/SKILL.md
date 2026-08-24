---
name: pickup
description: Resume work from a handoff summary written by /handoff in a previous session. Use when the user runs /pickup or asks to pick up where the last session left off.
---

# Pickup

Resume work from the handoff a previous session wrote.

## Steps

1. Read `<repo root>/.claude/handoff.md` (repo root from `git rev-parse --show-toplevel`; fall back to cwd). If it does not exist, tell the user there is no handoff and stop.
2. Cross-check the handoff against reality: current branch, `git status`, and that referenced files and lines still exist. The handoff reflects the moment it was written — where it disagrees with the working tree, trust the working tree and note the discrepancy.
3. Summarize for the user: the task, what is done, what is pending, and any discrepancies found.
4. Continue with the first pending item. If it hinges on a decision only the user can make, ask instead.
