# Metrics

Prometheus on leprechaun scrapes every server and pages through ntfy on
resource trouble: full disks, low memory, memory leaks, busy CPUs, OOM
kills, cgroups near their memory limit. gatus ([monitoring.md](monitoring.md)) answers "is it up";
this answers "is it healthy".

```
flake.tailnetAddresses -> exporters on each server (tailnet IP only)
                       -> prometheus scrape targets on leprechaun
prometheus rules -> alertmanager -> alertmanager-ntfy -> alert-send
```

## Hosts

[`tailnet.nix`](../modules/flake/tailnet.nix) defines
`flake.tailnetAddresses`. Each server sets its own entry in
`modules/hosts/<host>/imports.nix`. DNS
([`dns.nix`](../modules/dns/dns.nix)) reads the same map.

A host with an entry gets
[`metrics-exporters.nix`](../modules/nixos/core/metrics-exporters.nix):

- node_exporter on port 9100, with the systemd collector.
- cAdvisor on port 9101, covering every cgroup, so systemd services and
  podman containers both report memory and OOM events.

Both bind to the tailnet address, with `ip_nonlocal_bind` so they start
before tailscale. tailscale0 is a trusted interface, so no port opens.

Desktops have no entry, so they run no exporters.

## Rules

[`rules.yml`](../modules/nixos/server/metrics/rules.yml) holds every alert.
Each one reads the `host` label that the scrape config adds.

| Alert | Fires when |
|---|---|
| HostDown | an exporter misses scrapes for 5 minutes |
| DiskFull | a disk sits at 90% or more for 15 minutes |
| DiskFillingFast | a disk under 20% free empties within a day at its 6 hour rate |
| MemoryLow | under 10% memory available, ZFS ARC counted as free |
| MemoryRunningOut | under 30% available and the 6 hour trend hits zero within a day |
| CpuBusy | the host sits above 90% CPU for 2 hours |
| MemoryPressure | tasks stall on memory over 10% of the time |
| OOMKill, CgroupOOM | the kernel or a cgroup limit kills a process |
| CgroupNearMemoryLimit | a cgroup with a limit uses 90% of it |
| CgroupMemoryHigh | a service with no limit uses over 25% of host memory for an hour |
| CgroupCpuSpin | a service holds one core above 90% for an hour |

CpuBusy waits 2 hours, and CgroupCpuSpin skips nix-daemon, the GitHub
runners and `ci.slice`, so CI builds on leprechaun stay quiet. The cgroup
rules name the unit, which points at a leak.

HostDown waits 5 minutes so the nightly upgrade reboots stay quiet. See
[deploy.md](deploy.md).

`disk-alerts` still cleans up full disks every hour on these hosts, but
leaves paging to DiskFull.

### Testing rules

[`rules-tests.yml`](../tests/nixos/server/metrics/rules-tests.yml) feeds
synthetic series through `promtool test rules`. Add a case with each new
rule, then run:

```bash
nix build .#checks.x86_64-linux.metrics-rules
```

## Delivery

[`prometheus.nix`](../modules/nixos/server/metrics/prometheus.nix) runs
alertmanager on 127.0.0.1:9093. It groups by alert name and host, waits
30 seconds, and repeats a firing alert once a day.

`alertmanager-ntfy` receives its webhook and calls `alert-send` with
`ALERT_HOST` set to the alert's `host` label, so a puca alert reads
`puca: Disk full`, not `leprechaun: Disk full`. Several alerts in one
group become one message, for example `Disk full x3` with one mount per
line. Resolved alerts send at priority 3.

The `prometheus` VM check runs the whole chain into a fake ntfy.

## Blind spots

- leprechaun down means no metric alerts at all. gatus still pages for
  the host itself.
- Prometheus listens on 127.0.0.1:9090 only. Browse it with
  `ssh -L 9090:127.0.0.1:9090 leprechaun`.
