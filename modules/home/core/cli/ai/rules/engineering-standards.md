# Engineering Standards

Canonical source: `~/repositories/blizzard/modules/home/core/cli/ai/rules/engineering-standards.md`. Copies deployed to each agent (`~/.claude/rules/`, `~/.pi/agent/AGENTS.md`) come from Nix; edit the source only.

## Preferences

Do not store user preferences in agent memory. Write them in this file.

## Code Comments Must Earn Their Stay

Applies to every edit, in every language:

- Add a comment ONLY when it explains something the code cannot convey on its own — a non-obvious *why*, an external constraint, a subtle invariant. If the code already says it, do not restate it.
- Keep every comment as terse as possible: the fewest words that carry the point.
- Do NOT narrate dropped, alternate, or previous approaches. Production code has no reader who holds that history; contrasting against a design that no longer exists only misleads.
- Do NOT write comments that go stale — do not duplicate a value, restate the adjacent line, or describe transient state the code will outlive.

When in doubt, delete the comment and let the code speak.

## Investigations Must Cite Sources

Every factual claim in an investigation, debugging writeup, or root-cause analysis MUST link to the primary source it rests on. An unsourced claim is untrusted and forces the reader to re-find the evidence — wasting time and tokens.

- Logs → deep link to the exact log group/stream, scoped to the relevant time range.
- Metrics / alarms → direct link to the metric or dashboard.
- Code → permalink to the specific file and line range (e.g. a GitHub link pinned to a commit), not just a file name.
- Tickets, wikis, pipelines, dashboards → the URL, not a paraphrase.

If a source cannot be linked, say so explicitly rather than presenting the claim as established.
