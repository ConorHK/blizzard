# Tailnet policy

The Tailscale policy lives in
[`acl.nix`](../modules/tailnet/acl.nix) as a Nix attrset. `acl-sync`
pushes it to Tailscale, the same way `dns-sync` pushes DNS.

```
acl.nix (+ grants derived from host configs) -> tailnet-policy.json
  -> acl-sync: diff with live, validate, apply with --doit
```

## Derived parts

- `hosts` comes from `flake.tailnetAddresses`, so tests and grants can name
  `leprechaun`, `puca` and `bananach`.
- Every host with Prometheus enabled gets a grant to every other target in
  `blizzard.metrics.targets`, on the exporter ports. A new scrape target
  gets network access with no manual edit, and a test that proves it.

Everything else is hand-written, ported from the admin console.

## Tests

Tailscale runs `tests` and `sshTests` on every validate and apply, and
refuses a policy that fails them. They pin the grants that broke before:
gatus reaching Home Assistant, puca reaching leprechaun's voice services,
Prometheus reaching every exporter, and workstation ssh to servers.

## Sync

```bash
nix develop -c acl-sync          # diff with live, then validate
nix develop -c acl-sync --doit   # also apply
```

The API key sits in `modules/tailnet/secrets/tailscale-api-key.age`,
encrypted to the YubiKey only. No host decrypts it, so it needs no rekey.
Create it with `agenix edit`, holding an API access token from
https://login.tailscale.com/admin/settings/keys.

The apply sends the ETag from its own read as `If-Match`, so an edit made
in the admin console after the diff makes it fail instead of being
overwritten. Comments in the live policy do not survive an apply; they live
in `acl.nix` now.

Edit the policy in `acl.nix` only. A console edit shows up as a diff on the
next run, and the apply reverts it.
