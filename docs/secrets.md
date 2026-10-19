# Secrets

Secrets use [agenix](https://github.com/ryantm/agenix) with
[agenix-rekey](https://github.com/oddlama/agenix-rekey). You encrypt each
secret once, to a YubiKey master identity. `agenix rekey` then encrypts a
copy to each host's ssh key. Hosts decrypt only their own copies, at boot.

```
modules/.../secrets/foo.age      (master key: the YubiKey)
        | agenix rekey
        v
.secrets/<host>/<hash>-foo.age   (host key: /etc/ssh host key)
        | activation
        v
/run/agenix/foo                  (plaintext, on the host)
```

## The pieces

- The master identity is [`.secrets/age-yubikey-identity.pub`](../.secrets/age-yubikey-identity.pub).
  Only the YubiKey holds the private half, so creating, editing or rekeying
  a secret needs it plugged in.
- A backup FIDO2 key (ZUKEY 2) can also decrypt every source secret. Its
  recipient is [`.secrets/age-fido2-backup-recipient.pub`](../.secrets/age-fido2-backup-recipient.pub),
  set as `age.rekey.extraEncryptionPubkeys`. It uses
  `age-plugin-fido2-hmac` with no identity file and a PIN. Encrypting to it
  needs no token, so day to day only the YubiKey is used.
- Source secrets sit in `secrets/*.age` beside the module that uses them, for
  example [`modules/nixos/server/duckdns/secrets/`](../modules/nixos/server/duckdns/secrets/).
  The module points at its file with `age.secrets.<name>.rekeyFile`.
- Rekeyed copies sit in `.secrets/<host>/` for NixOS hosts, and
  `.secrets/homes/<home>/` for standalone homes. They are committed, so hosts
  and CI never need the YubiKey.
- Each host sets `age.rekey.hostPubkey` in its
  `configuration.nix` (for example
  [puca](../modules/hosts/puca/configuration.nix)). Homes set it in `home.nix`
  (for example [dullahan](../modules/hosts/dullahan/home.nix)).

## Where it is wired

- For NixOS, [`modules/nixos/core/agenix.nix`](../modules/nixos/core/agenix.nix)
  sits in `core`. It sets `storageMode = "local"` and
  `localStorageDir = .secrets/<hostName>`. It also aliases `secrets` to
  `age.secrets`.
- For Home Manager, [`modules/home/core/agenix.nix`](../modules/home/core/agenix.nix)
  decrypts into `~/.local/share/agenix`. Each home sets its own
  `localStorageDir`.
- At the flake level, [`modules/flake/agenix.nix`](../modules/flake/agenix.nix) points
  agenix-rekey at every `nixosConfigurations` and `homeConfigurations` entry.
- The dev shell in [`modules/flake/devshell.nix`](../modules/flake/devshell.nix)
  provides `agenix` and `age-plugin-yubikey`. It also sets
  `AGENIX_REKEY_ADD_TO_GIT=true`, so rekeyed files get staged for you.

## Add a secret

1. `nix develop`, with the YubiKey plugged in.
2. Create `modules/<path>/secrets/<name>.age` with `agenix edit`.
3. Reference it in the module with `age.secrets.<name>.rekeyFile = ./secrets/<name>.age;`.
4. `git add` the new `.age`. Nix flakes only see tracked files, so
   `agenix rekey` cannot find an untracked secret.
5. Run `agenix rekey`. New files appear under `.secrets/<host>/`, already
   staged.
6. Commit the source and rekeyed files together.

Consumers read the path, `config.age.secrets.<name>.path`, not the value. Pass it to services through
`LoadCredential` or an env file, never argv
(see [`duckdns.nix`](../modules/nixos/server/duckdns/duckdns.nix)).

## Add a host

1. Get its ssh host public key (`/etc/ssh/ssh_host_ed25519_key.pub`).
2. Set `age.rekey.hostPubkey` in its `configuration.nix`.
3. Run `agenix rekey` to create `.secrets/<host>/`.

The host build fails until step 3 lands, because agenix-rekey refuses to
build with missing rekeyed files.

## Backup key

After changing the master or backup keys, run `agenix update-masterkeys`
with the YubiKey plugged in. It re-encrypts every source secret to the
current key set.

To recover with only the backup key:

1. Plug it in and decrypt with the magic identity:
   `rage -d -j fido2-hmac modules/<path>/secrets/<name>.age`.
2. To make it the master, write its magic identity to a file with
   `age-plugin-fido2-hmac -m > .secrets/age-fido2-identity.txt`. Point
   `masterIdentities` at that file, then run `agenix update-masterkeys`.

## Expiring credentials

Some tokens expire or can be revoked. [`secret-expiry.nix`](../modules/nixos/core/secret-expiry.nix)
(in `core`) checks registered secrets daily, and alerts 14 days before expiry
(`warnDays`). Built-in probes check cachix tokens for write access and GitHub
tokens. Register a secret under `blizzard.secretExpiry.secrets`, as
[`github-runner.nix`](../modules/nixos/server/github-runner/github-runner.nix)
does.

## Guards

- `ripsecrets` runs in pre-commit
  ([`checks.nix`](../modules/flake/checks.nix)) and catches plaintext tokens
  committed by mistake.
- The `.age` files are safe to commit. Without a host key or the YubiKey,
  they are only ciphertext.
