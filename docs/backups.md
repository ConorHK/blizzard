# Backups

Each host backs up with restic to its own bucket, `restic-backup-<host>`.

```
restic.nix           schedule, alerts, restore drill; takes a repository URL
restic-secrets.nix   per-host repo password, shared ntfy topic
b2.nix               backend: bucket -> B2 S3 URL + per-host key
```

A host imports `restic`, `restic-secrets` and one backend module, and adds
paths with `restic.paths`. Modules add their own paths, so a host backs up
whatever its services declare.

## Secrets

All live in `modules/nixos/server/restic/secrets/`:

| File | Holds |
|------|-------|
| `<host>-password.age` | restic repo password |
| `<host>-b2.age` | `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` for a key scoped to that bucket |
| `restic-ntfy-topic.age` | alert topic, shared |

Keep every repo password in the password manager too. Without it a repo
cannot be restored, even with the bucket intact.

## Swapping the backend

1. Write a sibling of `b2.nix` that sets `restic.repository` from
   `restic.bucket` and `restic.environmentFile` from a per-host secret.
2. Copy each repo across with `restic copy --from-repo <old>`, keeping the password.
3. Swap the `restic-b2` import on each host.

## puca

puca stores only the backups Home Assistant makes itself, from
`<config>/backups`. Home Assistant encrypts them with its own key, which
restore also needs.
