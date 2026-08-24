# Syncthing handoff

State as of 2026-08-24.

## Working

- leprechaun runs syncthing as a system service and acts as the always-on hub.
- dullahan and leprechaun are connected; `share` reached 100% (10 items, ~6.3 GB).
- leprechaun's identity is `KGAUJQQ-HTI6NC4-PEYY4SO-BHTF63E-TGWZB6E-GZJZKRB-BWLIKEX-FNKMCQD`,
  produced by the `syncthing-key` agenix-rekey generator. `key.pem` is encrypted in
  `secrets/key.age`; `cert.pem` and `device-id` are public and committed.
- The share is deliberately **not** in `restic.paths`.

## TODO

### 1. Verify abhartach's device ID

`6UC67WT-CMLMJIP-JA6Z2H2-2H2ICCF-N7VRJBY-4XOMVIO-A6E7TN4-JVSW4A4` in
`modules/lib/syncthingDevices.nix` was recovered from a commented-out block in
`modules/hosts/dullahan/home.nix`. The machine was offline when it was committed,
so it has never been checked against the running daemon.

After `rebuild abhartach`:

```bash
journalctl --user -u syncthing | grep -i "device ID"
```

If it differs, correct the literal — it is the only place the value appears.

### 2. Put the desktop identities under agenix

abhartach and dullahan still use self-generated `cert.pem`/`key.pem` in
`~/.local/state/syncthing`, so their identities are not reproducible from the repo.

The same generator pattern applies — home-manager's syncthing module has the same
`cert`/`key` options as the NixOS one. Note that generating fresh keys **rotates**
those device IDs, so `syncthingDevices.nix` must change in the same commit or the
mesh breaks.

## Gotchas

- `syncthing-init` is `Type=oneshot` with `RemainAfterExit=true`, ordered
  `After=syncthing.service`. Stopping it does not re-run it, and starting
  `syncthing` alone will not pull it in. After wiping config, run
  `systemctl start syncthing-init` or the daemon comes up with no peers.
- Devices and folders are POSTed over the REST API by that unit, not written to
  disk by Nix. Deleting `config.xml` therefore discards the whole declarative
  state until it runs again.
- `agenix generate` ignores `AGENIX_REKEY_ADD_TO_GIT`. `git add` the new `.age`
  before `agenix rekey`, or the rekey fails — Nix cannot see untracked files.
- `services.syncthing.cert` takes a `str`. Use `"${./cert.pem}"`, never
  `toString ./cert.pem`: the latter drops string context, so the file is not part
  of the closure and never reaches the host. It fails only at runtime, and the
  `ExecStartPre` that installs it does not `set -e`, so the unit still starts and
  silently generates a throwaway identity.
