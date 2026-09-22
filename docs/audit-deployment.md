# Deploy the security fixes

## Before switching hosts

1. Review and add the new files to Git. Git-based flakes omit untracked files.
2. Connect the age identity, enter `nix develop`, and run `agenix rekey -a`. Puca needs encrypted copies of `restic-env`, `restic-password`, and `restic-ntfy-topic`. Review the generated files before committing.
3. Verify that the existing storage credentials can create a repository under `restic-backup-leprechaun/puca`. This uses a separate prefix in the existing bucket, not a new bucket.
4. Run the checks below. Selkie requires idmapped mount support on its home filesystem. The VM test checks the mount layout and Nix proxy, but does not certify the production ZFS dataset. Do not remove isolation if a mount fails.
5. Schedule the first backup before deploying. Immich and Calibre now pause during backups, and Puca pauses Home Assistant. Measure the full-library upload before accepting its daily outage.

```sh
nix build \
  .#checks.x86_64-linux.security-scripts \
  .#checks.x86_64-linux.claude-auto-mode-guard \
  .#checks.x86_64-linux.restic \
  .#checks.x86_64-linux.selkie-isolation \
  .#checks.x86_64-linux.clip
```

Deploy one host at a time after these checks pass. Keep a working administrative session open until login, container startup, and backups work.

## Verify backups

Restic runs as root so it can read subordinate-UID container files. Use the generated root wrapper rather than the `asc` alias:

```sh
sudo systemctl start restic-backups-service-data.service
sudo journalctl -u restic-backups-service-data.service -n 50
sudo restic-service-data snapshots
```

Confirm that the stopped applications restart. Matrix and Dawarich dumps must complete before the backup starts; either failure must notify the alert topic.

Restore into a new directory, not over live data:

```sh
restore_dir=$(mktemp -d)
sudo restic-service-data restore latest --target "$restore_dir"
```

Check restored file contents and ownership. Test database restores in a disposable instance before treating a snapshot as a recovery point. Puca's repository is independent of the leprechaun repository; run its checks on Puca too.

## Dawarich recovery

Recover the dump into the new restore directory above. The following commands replace database state: use them only in the disposable recovery instance, or after separately approving a production restore.

```sh
asc systemctl --user stop dawarich-app dawarich-sidekiq
sudo gzip -dc "$restore_dir/storage/data/dawarich/dumps/dawarich.sql.gz" \
  | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
  | asc podman exec -i dawarich-db psql --username=postgres
```

The dump contains the database role password at backup time. Reconcile it with the current agenix credential before starting the web and worker containers. Do not print credentials in the journal or shell history.

## Restricted tools

`podman-ro` accepts these forms only:

| Command | Arguments |
| --- | --- |
| `ps`, `images`, `info`, `version` | none |
| `events`, `stats` | none; finite output |
| `inspect`, `port` | container name |
| `logs` | container name, optional line count |

Inspection returns state, not environment variables. Logs can still contain application secrets; the journal group also grants broad log access.

`pi-jail` hides host runtime sockets and the Nix daemon. Host SSH-agent forwarding and direct Nix daemon builds are unavailable inside the jail. Network access remains enabled by default, including localhost. Explicit extra mounts or Bubblewrap arguments can weaken isolation.
