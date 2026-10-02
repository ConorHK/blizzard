# AGENTS.md

Guidance for coding agents working in this repository.

## Overview

Blizzard is a NixOS and Home Manager flake for five hosts:

| Host | Role |
|------|------|
| abhartach | Workstation |
| bananach | Monitor VPS (gatus), tailnet only |
| dullahan | Laptop |
| leprechaun | Home server: containers, nginx, backups, CI runner |
| puca | Home Assistant |

It uses flake-parts with import-tree: every `.nix` file under `modules/` is imported automatically. There is no import list.

## Commands

```bash
nix fmt                     # nixfmt and yamlfmt via treefmt
nix flake check             # hooks, unit checks and NixOS VM tests
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
nix develop                 # or direnv; provides the scripts below
rebuild <host>              # nh os switch on the host itself
rebuild-home <home>         # home-manager switch for a standalone home
check-hosts                 # eval every host without building
```

Pre-commit hooks: treefmt, deadnix, statix, shellcheck, ruff, yamllint, ripsecrets, flake-checker.

## Layout

- `modules/flake/`: flake-level options and outputs (`nixosHosts`, `homeConfigurations`, `monitoringChecks`, unfree and insecure allowlists, dev shell, checks, ISO).
- `modules/hosts/<host>/`: `imports.nix` registers the host and picks modules; `configuration.nix`, `hardware.nix`, `facter.json`, `disko.nix`, optional `home.nix`.
- `modules/nixos/core/`: imported by every host through `flake.modules.nixos.core`.
- `modules/nixos/desktop/`, `modules/nixos/server/`: opt-in modules, selected per host.
- `modules/home/`: Home Manager modules; `core` is the baseline, `desktop` the GUI set.
- `modules/lib/`: helpers exposed as `flake.lib` (`mkUser`, `mkDisko`, ssh keys, syncthing devices).
- `modules/packages/`: per-system packages, consumed as `inputs.self.packages.<system>.<name>`.
- `modules/theme/`: Stylix, opt-in targets only.

`nixosHosts.<host>` has one option, `system`. `mkHost` in `modules/flake/nixos.nix` combines `core` with `flake.modules.nixos."nixosConfigurations/<host>"`.

## Secrets

agenix-rekey with a YubiKey master identity (`.secrets/age-yubikey-identity.pub`). Source secrets sit next to their module as `secrets/*.age`; rekeyed copies live in `.secrets/<host>` and `.secrets/homes/<home>`. `git add` a new `.age` before `agenix rekey`, or Nix cannot see it.

## Deploys

puca, leprechaun and bananach auto-upgrade daily from the `deployed` branch, staggered an hour apart (`modules/nixos/core/update.nix`). CI fast-forwards `deployed` after every host builds on `main`. Desktops deploy by hand.

## Conventions

- `pipe-operators` is enabled; statix cannot parse it, so affected files sit in its ignore list in `modules/flake/checks.nix`.
- Container images carry a `# renovate: datasource=docker depName=...` comment on the line above `image =`, or Renovate never updates them.
- Every public nginx vhost needs a `flake.monitoringChecks` entry or a `blizzard.monitoring.exempt` entry; the build fails otherwise.
- VM tests live in `*-tests.nix` beside the module they cover.
- Never ssh to a host without the owner's approval.
