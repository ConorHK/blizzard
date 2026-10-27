# Ogham

Ogham is a git repo of markdown notes in `~/ogham`. Pi sessions record their
tasks and workers in it. You read and edit it in nvim. A private remote keeps
a copy off the host.

## Pieces

| Piece | Source | Role |
|---|---|---|
| Repo module | [`ogham.nix`](../modules/home/core/ogham/ogham.nix) | `programs.ogham`: clone and sync timer |
| CLI | [`ogham.sh`](../modules/home/core/ogham/ogham.sh) | `ogham init` and `ogham sync` |
| Pi extension | [`ogham/`](../modules/home/core/cli/ai/pi/ogham/) | `programs.pi.ogham`: `ogham_task`, `/task`, curation, wins, search |

A downstream flake imports `homeManager.ogham`, sets `remote`, and enables
`programs.pi.ogham`.

## Sync

Home Manager activation runs `ogham init`. With a remote and no
`~/ogham/.git`, it clones, keeping any files already in `~/ogham`; a failed
clone warns and retries on the next switch. Without a remote, it runs
`git init`. The CLI carries its own ssh, since activation runs with a bare
PATH.

`ogham sync` runs every 5 minutes from a systemd user timer. It commits
everything, rebases onto the remote, and pushes. A flock keeps runs from
overlapping. A failed rebase aborts and exits 1, so the repo stays as it was
until someone fixes it by hand.

## Layout

```
index.md                 every task: status, updated, next step
wins.md                  career wins, newest last
topics/<topic>.md        durable knowledge, dated entries
projects/<repo>/<slug>/
  <slug>.md              Goal, Status, Next, Decisions, Findings, Links, Log, Workers
  workers/<id>.md        one per pi session, written only by it
```

## Tasks and workers

The `ogham_task` tool (or `/task <title>`) binds a session to a task and
records the binding in the session, so resume restores it. Given a URL,
`/task` sends the agent a prompt to look up the item's ID and title, since
only the agent has the tools to read it. The slug comes from the last URL
path segment shaped like a ticket ID (`CR-123`, `V2429106601`), so it does
not depend on the fetched title. Without one, it takes the first bare number
with the two segments before it (`blizzard-pull-42`), since numbers repeat
across repos.

An orchestrator session starts workers in herdr panes with
`OGHAM_TASK=<repo>/<slug>` and `OGHAM_PARENT=<intercom id>`. Each worker
joins on startup and records its pane and intercom id, so the orchestrator
can reach it through intercom.

## Curation

After each agent run, the extension sends the run's transcript and the task
note to a side model, set by `programs.pi.ogham.settings.model`. The reply
is JSON. Status and Next are replaced each run, so a hand edit there lasts
only if the curator keeps it (it keeps Next items that are still open).
Decisions, Findings, Links (picked from URLs seen in the run) and Log only
append, so hand edits there survive. Before serializing the run, the
extension drops `ogham_task` calls, their results, and the `/task <url>`
prompt, so bookkeeping never reaches the note. Curation runs after the turn
and never blocks the user; shutdown waits up to 30 seconds for it.

Every write to a shared file (task note, `wins.md`, `index.md`, topics) holds
a lock, an atomic `mkdir` under the temp directory, and rereads the file
inside it. The curator applies its reply to that fresh copy, never to the
note it sent the model, so worker joins during a slow call survive. Writes go
to a `.tmp` file and rename into place; sync excludes `*.tmp` and
`.zvec-grep/`.

## Wins

A win is a result someone outside the team would recognize: a merged or
deployed change, a resolved incident or ticket, a measured gain, a launch.
Local progress is not a win. The curator records a win when a run reaches
such a milestone; `/task done` records the task's overall win if none is
recorded. The prompt includes the wins already recorded for the task, so
they are not repeated. `winGuidance` adds the user's own rules.

## Knowledge

`/task done` asks the side model to move durable findings and decisions into
`topics/<topic>.md`, reusing existing topics. On bind, the extension indexes
the repo with `zg` (local embeddings, `.zvec-grep/` kept out of git) and
searches it for the task's title and goal. The top hits from other tasks and
topics go into the system prompt with the task note's own sections.
