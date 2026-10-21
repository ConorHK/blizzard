# Container smoke tests

Renovate image bumps start on leprechaun, against a clone of production
data, before anyone merges them. The result lands as a `container-smoke`
commit status on the Renovate branch. Nothing in the run touches production
data or the network.

```
renovate.yml or the hourly timer -> container-smoke.yml on leprechaun
  -> nightly.sh: each undecided renovate/* branch
  -> ci.sh: containers whose image changed
  -> container-smoke@<id>: pod on a ZFS clone, no network
```

## 1. Dispatch

Two things dispatch
[`container-smoke.yml`](../.github/workflows/container-smoke.yml):

- [`renovate.yml`](../.github/workflows/renovate.yml), after Renovate pushes
  its branches.
- The `container-smoke-dispatch` timer on leprechaun
  ([`github-runner.nix`](../modules/nixos/server/github-runner/github-runner.nix)),
  every hour. GitHub cron runs hours late, and deferred runs need a retry.

The workflow runs on the self-hosted runner, one run at a time.

## 2. Pick branches

[`nightly.sh`](../modules/nixos/server/container-smoke/nightly.sh) lists the
`renovate/*` branches and skips any whose head already has a decided
`container-smoke` status. It runs
[`ci.sh`](../modules/nixos/server/container-smoke/ci.sh) on each of the rest,
from a copy of `ci.sh` taken from `main`, because branch copies may be stale.

## 3. Pick targets

`ci.sh` evaluates leprechaun's quadlet containers at the merge base and at
the branch head, and tests every container whose image changed. A branch
with no image change passes with "No image changes."

It builds the spec (`flake.containerSmoke.leprechaun`, from
[`container-smoke.nix`](../modules/nixos/server/container-smoke/container-smoke.nix)),
writes a request under `/var/lib/container-smoke/requests`, and starts
`container-smoke@<id>.service`. A polkit rule lets the runner user start
that unit and nothing else.

## 4. Run

[`run.sh`](../modules/nixos/server/container-smoke/run.sh) runs as root:

- Snapshots and clones the data dataset. Volumes under the data root map
  onto the clone, so writes never reach production.
- Blanks every other volume, plus each container's `emptyPaths`. Store
  paths and `/etc/localtime` mount as they are.
- Groups targets that share a `Requires`/`BindsTo` closure. Each group
  runs in its own pod, one after another, with no network and a cap of
  `containerSmoke.memory` (4g). Pod members share `127.0.0.1`, so two
  instances of one app in one pod would clash on ports.
- Passes a container with a port once the port answers and still answers
  10 seconds later, within 300 seconds. Passes a container with no port once
  it has stayed up for about 70 seconds.
- Destroys the pods, clone and snapshot on exit.

Results land in `results/<id>.json` (kept 7 days). Container logs hold app
data, so they stay root-only in `logs/<id>` (kept 14 days) and never reach CI.

## Upgrade windows

leprechaun upgrades at 06:00, with up to 5 minutes of random delay, and may
reboot ([`update.nix`](../modules/nixos/core/update.nix)). A reboot mid-run
kills the pod. [`gate.sh`](../modules/nixos/server/container-smoke/gate.sh)
defers a run when:

- `nixos-upgrade.service` is running,
- a reboot is scheduled, or
- `nixos-upgrade.timer` fires within one run's timeout (30 minutes). The
  unit stays inactive through the timer's random delay, so only the timer
  shows an upgrade is due.

A deferred run exits 75. `nightly.sh` marks the branch pending ("Waits for
the host upgrade to finish"), and the next hourly dispatch retries it.

## Statuses

| State | Description |
|---|---|
| success | Last line of the run, such as `web: pass port 8080 answered` |
| failure | First failing container and its reason |
| pending | Deferred by the gate |
