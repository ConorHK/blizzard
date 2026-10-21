# pi ogham

Tracks tasks, knowledge and wins in the ogham notes repo (`~/ogham`, or
`OGHAM_VAULT`).

Tell the agent the task, or run `/task <title>`. `/task <url>` asks the
agent to look up the ticket's ID and title, names the task after them, and
keeps the URL as `link`. The folder is named after the ID in the URL
(`dps-19022`), so a retitled ticket keeps its note.

After each agent run, a side model (`model` in `~/.pi/agent/ogham.json`)
reads the run and rewrites the task note's Status and Next, and appends
Decisions, Findings, Links and a Log line. When a run reaches a milestone
with value outside the team, such as a merged change, a deploy, or a
resolved ticket, it adds a win to `wins.md`. `index.md` lists every task
with its status and next step.

While bound, the system prompt carries the task note and related notes that
`zg` finds across the repo. `/task done` closes the task, moves its durable
findings into `topics/<topic>.md`, and records the task's win if one is not
recorded yet.

Each session writes its own worker note, `workers/<session>.md`. An
orchestrator starts workers in herdr panes with `OGHAM_TASK=<project>/<slug>`
and `OGHAM_PARENT=<its intercom id>`; they join on startup. `/task` alone
lists the workers. Bindings survive resume.

Settings: `model` (`provider/id`), `curate` (false turns the side model off),
`winGuidance` (extra rules for wins), `zg` (path to zg).
