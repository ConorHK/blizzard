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

`immich`, `photon` and `voice` are not opened in the firewall — they are reachable over the tailnet or through nginx only. `monitor.goosebox.org` proxies to gatus on bananach.

## puca services

| Module | Services | Ports |
|--------|----------|-------|
| `home-assistant` | home-assistant | 8123 |

## bananach services

| Module | Services | Ports |
|--------|----------|-------|
| `gatus` | gatus | 8080 (bound to tailnet address) |

Syncthing is core, so 22000 (TCP/UDP) and 21027 (UDP) are open on every host.

## intrusion detection

Host-based detection on all five hosts, imported via `modules/nixos/core/imports.nix`. Alerts push to ntfy using the `alert-ntfy-topic` agenix secret.

| Module | Detects | When |
|--------|---------|------|
| `alerts` | provides `alert-send` and the `alert-failure@` OnFailure template | — |
| `alerts-secret` | points `alerts` at the `alert-ntfy-topic` agenix secret | — |
| `auth-alerts` | Tailscale SSH grants/denials, sshd logins, sudo/su failures | live, journal follow |
| `tripwire-fast` | credentials, keys, setuid binaries | every 15 min |
| `tripwire-full` | the fast set plus listeners, units, modules | daily 01:30 |

`auth-alerts` is rate-limited; any suppressed entries are logged to `journalctl -u auth-alerts`.

### tripwire

Builds a manifest of live state, diffs it against `/var/lib/tripwire/baseline-<mode>`, alerts with the diff, then re-baselines so each change reports once. The two modes share one script and keep separate baselines.

| Mode | Tracked | Why this interval |
|------|---------|-------------------|
| `fast` | `passwd`/`group` entries, digests of `shadow`/`sudoers`/`sshd_config`, authorized-key and host-key fingerprints, setuid binaries and wrappers | changes only on deploy, so frequent checks are quiet |
| `full` | the above plus non-loopback listeners below port 32768, enabled units, loaded modules, non-symlink `/etc` entries | containers cycle and modules load on hotplug, so it needs a quiet slot |

- First run of each mode creates its baseline silently. Verify that baseline against what the flake declares before relying on it.
- `full` runs at 01:30 to stay clear of `nh clean` (00:00), dawarich (02:45), restic (03:00, which stops containers and would otherwise look like drift), and every autoUpgrade window (05:00+).
- Container image layers and `/nix/store` are pruned from the setuid scan; on leprechaun that is the difference between 1s and 50s+.

```
systemctl start tripwire-fast          # run now
rm /var/lib/tripwire/baseline-fast     # start a fresh baseline
```

### tests

`nix build .#checks.x86_64-linux.tripwire` boots a VM and drives the whole state machine: baseline creation, clean re-runs, setuid and account drift, re-baselining so a change reports once, and the fast/full split. It asserts on the delivered alert — title, priority, tags, diff body — by pointing `blizzard.alerts.endpoint` at a recorder inside the VM, so nothing leaves the machine and no secret is needed. `nix flake check` runs it; a nixpkgs bump re-runs it.

### auditd

Evaluated and deliberately not used — it does not work correctly against this deployment's login path. Do not re-add it without revisiting that.
