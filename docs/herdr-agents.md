# Herdr agent glue

Claude Code and pi get the same Herdr features. Each feature is one command
from the herdr home module. Each harness calls it from a thin adapter in its
own hook system.

```
Claude hook (claude/*.sh, claude.nix)  --+
                                         +--> herdr-* command --> hc, herdr-app, canvas file
pi extension (pi/*.ts)                 --+
```

| Command | Does | Claude adapter | pi adapter |
|---|---|---|---|
| `herdr-workspace-guard <folder>` | Prints other live agents in the same jj workspace or git worktree | SessionStart hook: `systemMessage` and `additionalContext` | `session_start` notify, `before_agent_start` hidden message |
| `herdr-tab-name <session> <prompt>` | Names a default-named tab after the first prompt, once per session | UserPromptSubmit hook | `input` event |
| `herdr-show` | Draws a page from stdin in the canvas sidebar; `--clear` empties it | `herdr-show` skill; SessionEnd clears | `show_ui` tool; `session_shutdown` clears |

The commands live in
[`agent-hooks/`](../modules/home/desktop/herdr/agent-hooks/) and
[`herdr-show/`](../modules/home/desktop/herdr/herdr-show/). They do nothing
outside a Herdr terminal (`HC_TERMINAL_ID` unset). Adapters check the command
is on PATH, so a host without the herdr module skips them.

## Rules the commands keep

- Subagents inherit `HC_TERMINAL_ID` but run headless. pi adapters act only in
  `tui` mode; Claude's subagents fire no session hooks.
- `herdr-tab-name` names a tab only while it has a default name: its number,
  "Claude Code", or pi's title. A name the user set stays. The label
  `herdr.named=<session>` on the terminal stops a second run.
- The namer runs `claude -p --model haiku` detached, without `HC_TERMINAL_ID`
  and with project settings only, so its own hooks stay quiet.
- `herdr-show` writes `$XDG_STATE_HOME/pi-ui/<terminal>.json` and sets the
  terminal's `pi.ui` label, which the canvas mod watches.

## Claude only

The status line (`claude/statusline.sh`) reads plan limits that only Claude
Code passes to its status line. pi's own footer shows model and context use.
