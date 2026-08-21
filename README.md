# blizzard

| Hostname     | Description                 |
| ----------   | ----------------------------|
| **abhartach**| Workstation PC              |
| **bananach** | Monitor VPS                 |
| **dullahan** | Laptop                      |
| **puca**     | HomeAssistant Fuji          |
| **leprechaun** | Home server               |

## leprechaun services

| Module | Services | Ports | Reverse proxy |
|--------|----------|-------|---------------|
| `actual-budget` | actual-server | 5006 | budget.lep.goosebox.org |
| `audiobookshelf` | audiobookshelf | 13378 | audiobookshelf.goosebox.org |
| `calibre` | calibre-web, shelfmark | 8183, 8084 | calibre.goosebox.org, shelfmark.goosebox.org |
| `changedetection` | changedetection.io, sockpuppetbrowser | 5000 | changedetection.lep.goosebox.org |
| `dawarich` | redis, postgis, app, sidekiq | 3001 | dawarich.lep.goosebox.org |
| `duckdns` | duckdns (timer, every 5 min) | — | — |
| `github-runner` | github-runner | — | — |
| `glance` | glance | 8092 | glance.lep.goosebox.org |
| `immich` | redis, postgres, machine-learning, server | 2283 | photos.lep.goosebox.org |
| `mealie` | mealie | 9925 | mealie.lep.goosebox.org |
| `music-assistant` | music-assistant | 8095, 8097 | music-assistant.goosebox.org |
| `nginx` | nginx, ACME (namecheap DNS-01) | 80, 443 | — |
| `photon` | photon | 2322 | photon.lep.goosebox.org |
| `qbittorrent` | qbittorrent, qbit-manage | 8080, 8181 | qbittorrent.lep, qbit-manage.lep |
| `restic` | restic (backup 03:00, freshness check 10:00) | — | — |
| `satisfactory` | satisfactory server | 7777 (TCP/UDP), 8888 | — |
| `smartd` | smartd | — | — |
| `voice` | wyoming-whisper, kokoro-fastapi, wyoming-openai | 10300, 10200 | — |
| `wireguard-gateway` | wireguard wg0 | 51820 (UDP) | — |

The Ports column is what each service listens on, not what is reachable. Only `music-assistant` (host network), `satisfactory` and `wireguard-gateway` are opened in the firewall; everything else binds `127.0.0.1` and is reachable through nginx or over the tailnet. `monitor.goosebox.org` proxies to gatus on bananach.

## puca services

| Module | Services | Ports |
|--------|----------|-------|
| `home-assistant` | home-assistant | 8123 |

## bananach services

| Module | Services | Ports |
|--------|----------|-------|
| `gatus` | gatus | 8080 (bound to tailnet address) |

Syncthing is core, so 22000 (TCP/UDP) and 21027 (UDP) are open on every host.

## login alerts

All five hosts alert when someone logs in, imported via `modules/nixos/core/imports.nix`. Alerts push to ntfy using the `alert-ntfy-topic` agenix secret.

| Module | Does | When |
|--------|------|------|
| `alerts` | provides `alert-send` and the `alert-failure@` OnFailure template | — |
| `alerts-secret` | points `alerts` at the `alert-ntfy-topic` agenix secret | — |
| `login-alerts` | alerts on every login | live, journal follow |

Logins are read from `systemd-logind`, which opens a session for every path that goes through PAM — sshd, console and greetd alike — so a single source covers all of them without per-service pattern matching. The alert names the user, and adds the PAM service and origin when the session is still open to be queried.

Tailscale SSH is being retired in favour of sshd on port 2222; the `tailscaleSsh` flag in `modules/nixos/core/network/tailscale.nix` still leaves both paths up, and flipping it to `false` drives `tailscale set --ssh=false` on every host. Only the PAM path alerts, so until that flip a Tailscale SSH login that bypasses PAM is not reported.

Nothing else pages: failed passwords, sudo refusals and system drift are deliberately not reported. Alerts are capped at ten per ten minutes; suppressed entries are logged to `journalctl -u login-alerts`.

### auditd

Evaluated and deliberately not used — it does not work correctly against this deployment's login path. Do not re-add it without revisiting that.

## tests

`nix flake check` runs everything below. The VM tests boot a real machine, so they
assert behaviour a build cannot: alerts are captured by a recorder inside the VM
(`blizzard.alerts.endpoint`), so nothing leaves the machine and no secret is needed.

| Check | Asserts | Runtime |
|-------|---------|---------|
| `login-alerts` | a real ssh login reported once with its service and origin, tailscale grants, that a tailscale session reaching PAM alerts once, that failures and drift stay quiet, the ten-per-window cap | ~30s |
| `alerts` | the `alert-failure@` OnFailure template pages | ~20s |
| `restic` | repository init, backup, byte-identical restore, container pause hooks, freshness on an empty and on a stale repository, failure paging | ~30s |
| `quadlet-switch` | a changed container definition actually restarts the rootless unit across a switch | ~45s |
| `lib` | `mkUser` and `mkDisko` outputs, including the `fido2` branch and the ESP `umask` | instant |

Two invariants are enforced as NixOS assertions instead, so they fail the host build:

- **Firewall vs. published ports** — a port opened in the firewall whose container binds `127.0.0.1` only is a stated intent the deployment does not have. Fails the build; there is no opt-out.
- **Monitoring coverage** — every public nginx vhost needs a `monitoringChecks` entry, or an explicit `blizzard.monitoring.exempt` entry saying why not.
