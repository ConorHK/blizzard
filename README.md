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
| `actual-budget` | actual-server | 5006 | budget.goosebox.org |
| `aqua-booking` | aqua-booking (timer 06:58, books at 07:00 Europe/London) | - | - |
| `audiobookshelf` | audiobookshelf | 13378 | audiobookshelf.goosebox.org |
| `calibre` | calibre-web, shelfmark | 8183, 8084 | calibre.goosebox.org, shelfmark.goosebox.org |
| `changedetection` | changedetection.io, sockpuppetbrowser | 5000 | changedetection.goosebox.org |
| `clip-server` | clip | 7391 (tailnet, wg0) | - |
| `dawarich` | redis, postgis, app, sidekiq | 3001 | location.goosebox.org |
| `duckdns` | duckdns (timer, every 5 min) | - | - |
| `freshrss` | freshrss | 8002 | rss.goosebox.org |
| `gatus-watch` | gatus-watch (probes bananach's gatus every 5 min) | - | - |
| `github-runner` | github-runner, deployed-lag (hourly) | - | - |
| `glance` | glance | 8092 | news.goosebox.org |
| `hister` | hister | 4433 | search.goosebox.org |
| `immich` | redis, postgres, machine-learning, server | 2283 | photos.goosebox.org |
| `immich-public-proxy` | immich-public-proxy | 3010 | share.photos.goosebox.org |
| `immich-stack` | immich-stack (cron, daily) | - | - |
| `matrix` | synapse, mautrix whatsapp/discord/meta bridges | 8008 | matrix.goosebox.org |
| `mealie` | mealie | 9925 | recipes.goosebox.org |
| `navidrome` | navidrome | 4533 | music.goosebox.org |
| `nextdns` | nextdns | 53 (wg0 only) | - |
| `nginx` | nginx, ACME (deSEC DNS-01) | 80, 443 | - |
| `ollama` | ollama (nomic-embed-text, for hister) | 11434 | - |
| `photon` | photon | 2322 | photon.goosebox.org |
| `qbittorrent` | qbittorrent, qbit-manage | 8080, 8181 | qbittorrent.lep, qbit-manage.lep |
| `restic` | restic (backup 03:00, freshness check 10:00) | - | - |
| `satisfactory` | satisfactory server | 7777 (TCP/UDP), 8888 | - |
| `smartd` | smartd | - | - |
| `syncthing-server` | syncthing hub for the `share` folder | 22000 (TCP/UDP), 21027 (UDP) | - |
| `voice` | wyoming-whisper, kokoro-fastapi, wyoming-openai | 10300, 10200 | - |
| `wireguard-gateway` | wireguard wg0 | 51820 (UDP) | - |

The Ports column is what each service listens on, not what is reachable. The firewall opens only `nginx`, `satisfactory`, `syncthing-server` and `wireguard-gateway`. `voice` and `clip-server` listen on every interface, but the firewall drops them outside the trusted `tailscale0` and `wg0`. Everything else binds `127.0.0.1`, mostly behind nginx. `monitor.goosebox.org` proxies to gatus on bananach.

## puca services

| Module | Services | Ports |
|--------|----------|-------|
| `home-assistant` | home-assistant | 8123 |

## bananach services

| Module | Services | Ports |
|--------|----------|-------|
| `gatus` | gatus | 8080 (bound to tailnet address) |

Syncthing ports (22000 TCP/UDP, 21027 UDP) open only where syncthing runs: abhartach, dullahan and leprechaun.

## alerts

All five hosts import these via `modules/nixos/core/imports.nix`, so every host alerts when someone logs in. Alerts push to ntfy using the `alert-ntfy-topic` agenix secret.

| Module | Does | When |
|--------|------|------|
| `alerts` | provides `alert-send` and the `alert-failure@` OnFailure template | - |
| `alerts-secret` | points `alerts` at the `alert-ntfy-topic` agenix secret | - |
| `login-alerts` | alerts on every login | live, journal follow |
| `update` | alerts when an auto-upgrade fails | its upgrade window |
| `secret-expiry` | alerts before a registered credential expires or stops working | daily, where secrets are registered (leprechaun) |
| `zfs-alerts` | alerts on ZFS scrub problems, faulted devices and data errors | ZFS hosts, via ZED |

`login-alerts` reads logins from `systemd-logind`, which opens a session for every PAM login, including sshd, console and greetd. One source covers them all, with no per-service patterns. The alert names the user, and adds the PAM service and origin if the session is still open.

Tailscale SSH has been retired in favour of sshd on port 22. `blizzard.tailscaleSsh` (`modules/nixos/core/network/tailscale.nix`) drives `tailscale set --ssh=<bool>` per host and defaults to `false`; only bananach enables it, having no LAN address and no open ports. Tailscale SSH bypasses PAM and so is never reported, which means bananach logins do not alert.

Nothing else pages. Failed passwords, sudo refusals and system drift go unreported by design. Alerts are capped at ten per ten minutes; suppressed entries are logged to `journalctl -u login-alerts`.

### auditd

Not used. It does not work with this deployment's login path. Do not add it back without checking that again.

## tests

`nix flake check` runs everything below. The VM tests boot a real machine, so they
assert behaviour a build cannot. A recorder inside the VM captures alerts
(`blizzard.alerts.endpoint`), so nothing leaves the machine and no secret is needed.

| Check | Asserts | Runtime |
|-------|---------|---------|
| `alerts` | the `alert-failure@` OnFailure template pages, alerts raised while ntfy is down are held and drain once it is back, a hardened caller can queue and deliver, a payload ntfy rejects is dropped | ~20s |
| `aqua-booking` | dry runs book nothing, a free seat books and notifies, a full class joins the waitlist, a cancelled booking is never rebooked, a lost response is never double-booked | VM |
| `aqua-booking-unit` | the package's Python unittest suite | instant |
| `auto-mode-guard` | crafted tool calls are denied or deferred as the regression suite expects | instant |
| `bitbang` | serve runs as the service account, the view is read-only without `-upload`, uploads land only in `/upload`, the session ends with serve | VM |
| `clip` | slots round-trip between phone and mailbox, utf-8 survives byte for byte, a slot name cannot escape the state directory | VM |
| `deployed-lag` | a main commit CI has not promoted pages once past the threshold, promotion reports recovery, a rewritten main re-arms instead of wedging, fetch failures page once on the third miss | VM |
| `gatus-relay` | an outage sends one batched message, recovery is reported once, pending alerts survive a relay restart | VM |
| `gatus-watch` | short gatus outages ride through, the third missed probe pages once, recovery is reported | VM |
| `hyprland-<host>` | each Hyprland host's config passes `hyprland --verify-config` | instant |
| `lib` | `mkUser` and `mkDisko` outputs, including the `fido2` branch and the ESP `umask` | instant |
| `login-alerts` | a real ssh login reported once with its service and origin, tailscale grants, that a tailscale session reaching PAM alerts once, that failures and drift stay quiet, the ten-per-window cap | ~30s |
| `pi-advisor`, `pi-ttsr` | the pi extensions' node test suites | instant |
| `pi-extensions-<home>` | every pi package manifest entry exists, every extension loads in headless pi with no handler errors, and pi-subagents finds the pi modules its background runs need | instant |
| `pi-jail` | a trusted user's jailed `nix` call reaches the daemon untrusted, host abstract sockets and loopback services stay out of reach, other hosts stay reachable, `/run` holds only `current-system` and an empty runtime dir | ~3 min without KVM |
| `podman-egress-watchdog` | a routeless container netns pages once, repeats stay quiet, recovery clears state | VM |
| `pre-commit`, `treefmt` | the pre-commit hooks and formatting | instant |
| `quadlet-switch` | a changed container definition actually restarts the rootless unit across a switch | ~45s |
| `restic` | repository init, backup, byte-identical restore, container pause hooks, freshness on an empty and on a stale repository, failure paging | ~30s |
| `restic-zfs` | restic reads the ZFS snapshot rather than live files, containers are back before restic reads | VM |
| `secret-expiry` | probe-reported expiry warns inside the window, rejected credentials page with the reason, a secret with no known expiry asks for one | VM |
| `tests-mirror` | every file under `tests/` has a matching `modules/` path | instant |
| `waybar-<check>-<host>` | waybar commands resolve, every dispatch it can emit is valid Hyprland Lua | instant |
| `zfs-alerts` | a healthy scrub stays quiet, a faulted vdev pages through `alert-send` | VM |

Two NixOS assertions fail the host build instead:

- No firewall port may lead to a container that binds only `127.0.0.1`. There is no opt-out.
- Every public nginx vhost needs a `monitoringChecks` entry, or a `blizzard.monitoring.exempt` entry that says why not.
