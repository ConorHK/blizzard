# Monitoring

gatus on bananach watches every public service. A host with an nginx vhost
that no check covers fails to evaluate.

```
flake.monitoringChecks (any module) -> specialArgs -> gatus endpoints on bananach
                                                   -> coverage assertion on every host
```

## Declaring a check

Checks live at the flake level, not inside a host, so any module can
declare one next to the service it watches.
[`modules/flake/monitoring.nix`](../modules/flake/monitoring.nix) defines
the option:

```nix
flake.monitoringChecks.immich = {
  name = "immich";
  url = "https://photos.lep.goosebox.org";
};
```

The defaults are `interval = "1m"` and `conditions = [ "[STATUS] == 200" ]`.
Host liveness checks use `tcp://` URLs with `[CONNECTED] == true`
(see [`leprechaun/imports.nix`](../modules/hosts/leprechaun/imports.nix)).

## How checks reach every host

`mkHost` in [`modules/flake/nixos.nix`](../modules/flake/nixos.nix) passes
the full list to every host as the `monitoringChecks` specialArg. Two
modules use it:

- [`gatus.nix`](../modules/nixos/server/gatus/gatus.nix) turns each check
  into a gatus endpoint. Only bananach imports it.
- [`monitoring-coverage.nix`](../modules/nixos/core/network/monitoring-coverage.nix)
  asserts coverage on every host.

So a check declared in a leprechaun module ends up in bananach's gatus
config, with no host-to-host wiring.

## The coverage rule

On each host, the assertion collects every nginx vhost that:

- is not the `default` catch-all, and
- has a dot in its name (skips `localhost` and similar).

Each one must be a substring of some check's `url`, or appear in
`blizzard.monitoring.exempt`. Otherwise evaluation fails with
`no monitoringChecks entry covers <vhost>`.

The match is a substring test, so a check on `https://photos.lep.goosebox.org/api/ping`
covers the `photos.lep.goosebox.org` vhost.

Exempt a vhost only when watching it makes no sense. bananach exempts
`monitor.goosebox.org`, gatus's own UI
([`bananach/configuration.nix`](../modules/hosts/bananach/configuration.nix)).

## Maintenance windows

Two levels silence alerts during planned downtime.

- gatus's global `maintenance` block (06:00, 70m) silences every
  endpoint. It covers leprechaun's auto-upgrade reboot.
- `maintenanceWindows` silences one check. puca uses one at 05:00
  for its own reboot ([`puca/imports.nix`](../modules/hosts/puca/imports.nix)).

These windows must cover the upgrade windows in
[`update.nix`](../modules/nixos/core/update.nix), plus 10 minutes to boot.
The `upgrade-windows` check
([`upgrade-windows.nix`](../modules/flake/upgrade-windows.nix)) fails when a
rebooting host has a check that no window silences. See [deploy.md](deploy.md).

## Alert delivery

- [`relay.nix`](../modules/nixos/server/gatus/relay.nix) receives gatus
  alerts and batches them for 90 seconds into one ntfy notification. One
  outage that trips many endpoints sends one alert.
- gatus crashing fires `alert-failure@gatus.service`.
- bananach going down silences gatus itself. leprechaun's
  [`gatus-watch`](../modules/nixos/server/gatus/watch.nix) probes gatus
  every 5 minutes and pages after 3 straight failures.

## Add a public service

1. Add the nginx vhost in the service module.
2. Add `flake.monitoringChecks.<name>` in the same file.
3. Build the host. A missing check fails here, not in production.
