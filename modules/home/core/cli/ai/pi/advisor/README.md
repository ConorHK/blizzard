# pi advisor

A second model reviews each turn of the main agent and injects notes. Ported from
[oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT); see its `docs/advisor-watchdog.md`.

The advisor is its own pi session with read-only tools (`read`, `grep`, `find`, `ls`) and
one `advise(note, severity)` tool. Each review gets only the new part of the transcript.
It also gets your `AGENTS.md` files and any `WATCHDOG.md`, advisor-only guidance from
`~/.pi/agent/WATCHDOG.md` (`programs.pi.advisor.watchdog`) and, in trusted projects,
`WATCHDOG.md` or `.pi/WATCHDOG.md` from the repo root down to cwd.

| Severity | Delivery |
|---|---|
| `nit` | Shown, and sent with the next turn |
| `concern` | Steers the running agent, or wakes it if it stopped mid-work; after a final answer it is only shown |
| `blocker` | Steers or wakes the agent, even after a final answer |

A guard drops filler ("lgtm"), repeats, and notes past the per-review budget. After a
concern interrupts, later concerns become nits for `immuneTurns` turns. After you press
Esc, notes are shown but never restart the agent. Subagent children run unadvised.

`/advisor` toggles it for the session; `/advisor status` shows reviews and cost;
`/advisor dump` shows the advisor transcript.

Settings in `~/.pi/agent/advisor.json` (`programs.pi.advisor.settings`): `enabled`,
`model` (`provider/id[:level]`, default the session model and level), `reviewMode`
(`turn` or `agent-end`), `reviewInterval`, `maxNotesPerUpdate` (4), `immuneTurns` (3),
`syncBacklog` (`off`, or `strict` to wait for reviews before the agent stops), `tools`.
