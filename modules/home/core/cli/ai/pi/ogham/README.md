# pi ogham

Tracks what each pi session works on in the ogham notes repo (`~/ogham`, or
`OGHAM_VAULT`).

Tell the agent the task, or run `/task <title>`. `/task <url>` asks the
agent to look up the ticket's ID and title, names the task after them, and
keeps the URL as `link`. The folder is named after the ID in the URL
(`dps-19022`), so a retitled ticket keeps its note. The `ogham_task` tool
creates `projects/<repo>/<slug>/<slug>.md` and binds the session to it. Each
session writes only its own worker note, `workers/<session>.md`, so parallel
sessions never edit the same file. The extension updates `status`
(working, idle, closed, done) and logs the first line of each reply. A
joining worker appends a link to the task note's `## Workers` list. `/task`
alone, or `ogham_task` with no arguments, lists the workers with status, pane
and intercom id.

An orchestrator starts workers in herdr panes with `OGHAM_TASK=<project>/<slug>`
and `OGHAM_PARENT=<its intercom id>`; they join on startup. `/task join
<project>/<slug>` joins by hand, and `/task done` closes the task. Bindings
survive resume. The `ogham sync` timer commits and pushes the repo.
