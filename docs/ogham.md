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
everything, fetches, rebases onto the remote, and pushes. A flock keeps runs
from overlapping. A failed fetch exits 1 and retries next run. A failed
rebase aborts, exits 1, and writes `.git/ogham-sync-error`; every new pi
session warns while it exists, and the next clean sync removes it.

Three rules keep conflicts rare:

- `index.md` and `wins.md` are rebuilt on each host from the notes, so they
  stay out of git. A `wins.md` in the old single-file format stays synced
  until pi migrates it, which adds a marker line that sync looks for.
- Each win is its own file, and `topics/*.md` only grow at the end, so topics
  merge with git's `union` driver, which keeps both sides
  (`.git/info/attributes`).
- Worker notes are written by one session only.

Two hosts that edit the same task note within 5 minutes still conflict, and
a person resolves it.

## Layout

```
index.md                 every task: status, updated, next step (local)
wins.md                  every win, grouped by initiative (local)
wins/<date>-<title>.md   one win: fields in frontmatter, story in the body
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
path segment shaped like a ticket ID (`CR-123`, `V1000000001`), so it does
not depend on the fetched title. Without one, it takes the first bare number
with the two segments before it (`blizzard-pull-42`), since numbers repeat
across repos.

With `askOnStart`, a new interactive session asks for its task. It offers
a new ticket or title, the 7 most recently updated open tasks, any
follow-ups (see below), and None.
A new ticket goes through the same path as `/task`. None or Escape leaves
the session unbound. Resumed and reloaded sessions, sessions with messages,
workers started with `OGHAM_TASK`, and print, json and rpc modes never ask.
The dialog does not block startup, so other extensions still load.

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

The transcript holds fetched pages and tickets, so the curator is told to
treat it as data. The extension drops any link the run never showed, and
cuts the query from URLs that carry credentials (presigned URLs, tokens)
before it writes anything, since sync pushes every note to the remote.

Every write to a shared file (task note, `wins.md`, `index.md`, topics) holds
a lock, an atomic `mkdir` under `~/.cache/ogham-locks`, and rereads the file
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

Wins are the career-review dataset, so each one is a file whose frontmatter
holds fields that a query (for example Obsidian Dataview) can group and
filter:

| Field | Meaning |
|---|---|
| `date`, `task` | when, and the task note it came from |
| `initiative` | the larger project, copied from the task |
| `category` | reliability, latency, cost, toil, security, quality, launch, other |
| `role` | led or contributed |
| `metric`, `before`, `after` | the measured change, only from real numbers |
| `scope` | services, regions, hosts, teams, or customers covered |
| `measured`, `result` | when the user added the measured result, and their words |
| `impact_after` | snooze date for the impact prompt, or `never` |
| `tickets`, `sims`, `code`, `docs` | artifacts: lists of URLs |

Artifacts come from every URL in the task note plus the win's evidence,
sorted by regex rules on the URL. The built-in rules know only public hosts:
GitHub issues, pull requests, and commits, GitLab merge requests and
commits, Atlassian issues, and Google Docs. Rules for an employer's internal
hosts belong in a private flake, in `programs.pi.ogham.settings.artifactRules`:

```nix
programs.pi.ogham.settings.artifactRules = {
  tickets = [ ''^https://tickets\.example\.com/[A-Z]?\d+'' ];
  sims = [ ''^https://issues\.example\.com/issues/[\w-]+'' ];
  code = [ ''^https://code\.example\.com/reviews/CR-\d+'' ];
  docs = [ ''^https://wiki\.example\.com/'' ];
};
```

Settings rules run before the built-in ones, and a bad pattern warns at
session start. For tickets, SIMs, and code, the regex match is the stored
URL, so a rule that stops before `/revisions/2` or `/communication` collapses
repeats; docs keep the whole URL without its anchor. SIMs dedupe by their
last path segment, so one item on two hosts counts once. URLs no rule matches
(code browsing, pipelines, dashboards, short links) are not artifacts.

A win's lists grow when a later run adds links to its task, when the task
closes, and at each session start, which also fills in wins recorded before
artifacts existed. The curator keeps every artifact URL a run shows in the
task's Links section for that reason.

The body keeps the title, summary, impact, evidence links, and a link back to
the task. `wins.md` lists every win under its initiative, newest first, with
its artifact counts.

A task's initiative is its parent epic, program, or goal, as `<ID>: <name>`.
The curator sets `initiative` in the task's frontmatter the first time a run
names it, and never overwrites it, so a hand edit wins.

## Follow-ups

Impact usually shows up weeks after a change ships, and the curator never
invents numbers. With `askOnStart`, the start prompt also lists up to 3 of
each:

- `Impact:` a win older than 14 days with no `after` or `measured`, or a task
  in review or done for 14 days with no win. The answer, ideally
  `metric: before -> after`, goes into the win's fields; for a task, it
  creates the win. Escape asks again in 14 days; `none` stops asking.
- `Close:` an open task the curator marked `resolved` (its goal is met and
  nothing in Next stays open), or one not updated in 21 days. "Close it" runs
  the same close as `/task done` in the background; "Not yet" asks again in
  14 days (`close_after`). A later run that reports work in progress clears
  `resolved`.

After a follow-up the prompt shows again, so the session can still pick its
task.

## Knowledge

`/task done` asks the side model to move durable findings and decisions into
`topics/<topic>.md`, reusing existing topics. On bind, the extension indexes
the repo with `zg` (local embeddings, `.zvec-grep/` kept out of git) and
searches it for the task's title and goal. The top hits from other tasks and
topics go into the system prompt with the task note's own sections, framed
as data from past runs, not instructions.
