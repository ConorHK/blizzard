# Ogham

Ogham is a git repo of markdown notes in `~/ogham`. Pi sessions record their
tasks and workers in it. You read and edit it in nvim. A private remote keeps
a copy off the host.

## Pieces

| Piece | Source | Role |
|---|---|---|
| Repo module | [`ogham.nix`](../modules/home/core/ogham/ogham.nix) | `programs.ogham`: clone and sync timer |
| CLI | [`ogham.sh`](../modules/home/core/ogham/ogham.sh) | `ogham init` and `ogham sync` |
| Pi extension | [`ogham/`](../modules/home/core/cli/ai/pi/ogham/) | `programs.pi.ogham`: the `ogham_task` tool and `/task` |

A downstream flake imports `homeManager.ogham`, sets `remote`, and enables
`programs.pi.ogham`.

## Sync

Home Manager activation runs `ogham init`. With a remote and no `~/ogham`, it
clones; a failed clone warns and retries on the next switch. Without a
remote, it runs `git init`. It leaves an existing directory without `.git`
alone.

`ogham sync` runs every 5 minutes from a systemd user timer. It commits
everything, rebases onto the remote, and pushes. A flock keeps runs from
overlapping. A failed rebase aborts and exits 1, so the repo stays as it was
until someone fixes it by hand.

## Tasks and workers

```
projects/<repo>/<slug>/
  <slug>.md          task note: goal, log, workers list
  workers/<id>.md    one per pi session, written only by it
```

The `ogham_task` tool (or `/task <title>`) binds a session to a task and
records the binding in the session, so resume restores it. While bound, the
system prompt carries the task note path. The extension sets the worker
note's `status` on agent start, agent end and shutdown, and logs the first
line of each reply. A new worker appends a link to the task note's
`## Workers` list, which stays the last section so appends land there.
`/task` alone lists each worker's status, pane and intercom id.

An orchestrator session starts workers in herdr panes with
`OGHAM_TASK=<repo>/<slug>` and `OGHAM_PARENT=<intercom id>`. Each worker
joins on startup and records its pane and intercom id, so the orchestrator
can reach it through intercom.
