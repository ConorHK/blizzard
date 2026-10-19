# Deploy flow

A commit on `main` reaches the servers in three stages: CI builds it, CI
promotes it to `deployed`, and each server pulls `deployed` in its own
upgrade window. Desktops never auto-upgrade.

```
push main -> CI: checks + every host builds -> fast-forward deployed
          -> puca 05:00 -> leprechaun 06:00 -> bananach 07:00
```

## 1. CI builds everything

[`.github/workflows/build.yml`](../.github/workflows/build.yml) runs on every
push, on the self-hosted runner on leprechaun
([`github-runner.nix`](../modules/nixos/server/github-runner/github-runner.nix)).

- `check` builds every `checks.x86_64-linux` output. It evaluates them one at
  a time, because evaluating all at once peaks near 7G. VM tests run one at a
  time, because parallel VMs miss their boot timeouts.
- `discover` lists `nixosConfigurations` from the flake, so adding a host
  adds it to the build matrix.
- `build-machines` builds each host's toplevel and pushes the closure to the
  `conorhk` cachix cache. Hosts then substitute instead of building.

Concurrency cancels superseded runs on branches, but not on `main`. Every
`main` run must finish so `deployed` advances.

## 2. CI promotes to `deployed`

The `promote` job runs only on `main`, after every host builds. It pushes
`$GITHUB_SHA` to `deployed` without force, so `deployed` only fast-forwards.

- A failed check or host build blocks promotion. Servers keep running the
  last good commit.
- Runs can finish out of order. If `deployed` already contains the commit,
  the job exits cleanly instead of rewinding.

## 3. Servers pull in staggered windows

[`modules/nixos/core/update.nix`](../modules/nixos/core/update.nix) sits in
`core`, so every host gets it. It points `system.autoUpgrade` at
`github:conorhk/blizzard/deployed` and allows a reboot inside the host's
window (Europe/Dublin, from
[`misc.nix`](../modules/nixos/core/misc.nix)).

| Order | Host | Window | Why this slot |
|---|---|---|---|
| 1 | puca | 05:00-06:00 | Canary. A bad commit breaks Home Assistant first. |
| 2 | leprechaun | 06:00-07:00 | Matches gatus's global maintenance window. |
| 3 | bananach | 07:00-08:00 | Runs gatus, so it goes last. |

The hour gaps mean a bad commit never takes down every host at once, so a
host that still runs can send the alert.

abhartach and dullahan set `autoUpgrade.enable = false`
([abhartach](../modules/hosts/abhartach/configuration.nix),
[dullahan](../modules/hosts/dullahan/configuration.nix)). Deploy them with
`rebuild <host>`.

## Monitoring around the reboots

Each reboot would page without these windows.

- For leprechaun, gatus's global `maintenance` (06:00, 70m) in
  [`gatus.nix`](../modules/nixos/server/gatus/gatus.nix) silences every
  endpoint during its reboot.
- For puca, its own `maintenanceWindows` entry (05:00, 70m) in
  [`puca/imports.nix`](../modules/hosts/puca/imports.nix) silences only
  its endpoint.
- When bananach reboots, gatus itself goes down. leprechaun's `gatus-watch`
  ([`watch.nix`](../modules/nixos/server/gatus/watch.nix)) probes every 5
  minutes and pages after 3 straight failures, so a reboot under 15 minutes
  stays quiet.

The `upgrade-windows` check
([`upgrade-windows.nix`](../modules/flake/upgrade-windows.nix)) enforces the
first two. Move a window in `update.nix` without moving its maintenance
window, and CI fails. It skips the gatus host, which `gatus-watch` covers.

Other jobs avoid the windows. restic backs up at 03:00
([`restic.nix`](../modules/nixos/server/restic/restic.nix)), because a reboot
mid-backup leaves a stale lock, and the stopped unit never fires
`OnFailure`. Container smoke runs defer while an upgrade is running or
due ([container-smoke.md](container-smoke.md)).

## Failure alerts

| Failure | Signal |
|---|---|
| Upgrade fails on a host | `nixos-upgrade` fires `alert-failure@nixos-upgrade.service` |
| CI stops promoting | `deployed-lag` on leprechaun pages after 12h |
| `deployed-lag` cannot fetch the repo | Pages after 3 hourly misses |
| gatus down | `gatus-watch` pages after 3 failed probes |

[`deployed-lag.nix`](../modules/nixos/server/deployed-lag.nix) checks hourly
whether the newest `main` commit has reached `deployed`. It sends "Deploys
stalled" once the commit has waited `thresholdHours` (12 by default), and
"Deploys resumed" once CI catches up.

## Common tasks

| Task | Steps |
|---|---|
| Ship now | Push to `main` and wait for `promote`. Servers pick it up at their next window. |
| Ship before the window | Once `promote` finishes, run `rebuild <host>` on the host. |
| Hold a deploy | Do nothing. A red CI run blocks `deployed` on its own. |
| Roll back | Push a revert to `main`. `deployed` never rewinds, so a revert is the only way back. |
