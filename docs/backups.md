# Backups

Each backup is a job under `blizzard.backup.jobs.<name>`, with its own
restic repository and bucket.

```
modules/nixos/server/backup/
  backup.nix    engine: one restic job, alerts, restore drill per job
  b2.nix        backend: bucket -> B2 S3 URL
  secrets.nix   shared ntfy topic
  phone.nix     the phone job, fed by syncthing
  home.nix      desktop home directories
```

A server imports `backup`, `backup-secrets` and one backend module,
then passes each job its secrets.

| Job | Hosts | Bucket | Runs |
|-----|-------|--------|------|
| `service-data` | every server | `restic-backup-<host>` | 03:00 |
| `phone` | leprechaun, via `backup-phone` | `restic-backup-phone` | 01:30 |
| `home` | abhartach, dullahan, via `backup-home` | `restic-backup-<host>` | 03:00 or next boot |

Service modules add their paths to `jobs.service-data`, so a host backs up
whatever its services declare. A job with no paths gets no units.

## Per job

Every job `<name>` gets:

- `restic-backups-<name>`: the backup; a failure pages "Backup failed".
- `restic-freshness-<name>`, daily at 10:00, unless `freshness = false`. Alerts on a snapshot over
  26h old, a file in `dumpPaths` over 26h old, or a `freshPaths`
  directory with no new file in `freshMaxAge` hours (default 48).
- `restic-restore-drill-<name>`, Sundays at 12:00. Restores sample files
  and databases and compares them with disk.
- `restic-zfs-snapshot-<name>`, when `zfsDatasets` is set. Snapshots are
  named `<dataset>@restic-<name>`.

## Secrets

Each job takes its secrets as `passwordFile` and `environmentFile`. The
host declares them, in `modules/hosts/<host>/secrets/`:

| File | Holds |
|------|-------|
| `restic-password.age` | `service-data` repo password |
| `restic-env.age` | `service-data` B2 key |
| `<job>-backup-password.age` | job repo password (generated) |
| `<job>-backup-b2.age` | job B2 key |

Only the alert topic, `restic-ntfy-topic.age`, is shared; `backup-secrets`
holds it. B2 keys hold `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`,
scoped to one bucket. Renaming a secret forces a rekey; moving its file
does not.

Keep every repo password in the password manager too. Without it a repo
cannot be restored, even with the bucket intact.

## Adding a job

1. Set `blizzard.backup.jobs.<name>` with `paths` and, if needed, `bucket`
   and `schedule`.
2. Create the bucket and a key scoped to it.
3. In the host config, declare both secrets and pass their paths to the job.
4. `agenix edit` the B2 file, `agenix generate` the password, `git add`
   both, then `agenix rekey`.

## Swapping the backend

1. Write a sibling of `b2.nix` that sets each job's `repository` from its
   `bucket`.
2. Copy each repo across with `restic copy --from-repo <old>`, keeping the password.
3. Swap the `backup-b2` import and each job's `environmentFile`.

## Phone

```
phone app exports -> syncthing folder phone-backup -> restic 01:30 -> B2
```

- `backup-phone` fails to build without syncthing. leprechaun passes
  the job its secrets.
- leprechaun holds the folder receive-only; the phone sets it Send Only,
  so nothing flows back.
- Apps export into their own subfolder, for example `signal/`.
- The folder is a `freshPaths` entry with a 2 week window, since some
  apps export only by hand. Syncthing keeps the phone's mtimes.

Restore needs the restic password, then each app's own backup passphrase.

## Desktops

`backup-home` backs up `~/.ssh`, `~/.gnupg`, `~/docs`, `~/media`
(not `media/games`) and `~/backup`. Drop anything else worth keeping in
`~/backup`. The timer is Persistent, so a run missed while the machine
was off happens at next boot. There is no freshness alert, since desktops
sit off for days; the failure alert and restore drill still run.

## puca

puca stores only the backups Home Assistant makes itself, from
`<config>/backups`. Home Assistant encrypts them with its own key, which
restore also needs.
