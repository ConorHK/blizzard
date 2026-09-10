---
name: handoff
description: Write a handoff summary of the current session so a fresh Claude session can resume the work with /pickup. Use when the user runs /handoff or asks to hand off work before ending a session.
---

# Handoff

Capture the session's state in a file a fresh Claude session can resume from.

## Steps

1. Resolve the target path: `<repo root>/.claude/handoff.md`, where repo root comes from `git rev-parse --show-toplevel`. Outside a git repo, use `<cwd>/.claude/handoff.md`.
2. Ensure git ignores it, without touching tracked files:
   - If `git check-ignore -q .claude/handoff.md` already succeeds, skip this step.
   - Otherwise append `.claude/handoff.md` to `.git/info/exclude`.
3. Write the file, overwriting any previous handoff:

   ```markdown
   # Handoff — <date and time>

   ## Task
   <the overall goal, one or two sentences>

   ## State
   - Branch: <branch>; <clean, or summary of staged/unstaged changes>
   - <what is complete, with file:line references>
   - <what was verified (tests run, builds passed) and what was not>

   ## Pending
   - <remaining work, most important first>

   ## Context a fresh session needs
   - <non-obvious decisions and why>
   - <dead ends already ruled out>
   - <commands that work (build, test, run)>
   ```

4. Fill it from the actual conversation: decisions made, approaches rejected, verification status. Omit sections with nothing to say; never pad.
5. Confirm to the user: the path written and that git ignores it.
