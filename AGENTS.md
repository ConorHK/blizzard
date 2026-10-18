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

It uses flake-parts with import-tree: every `.nix` file under `modules/` and `tests/` is imported automatically. There is no import list.

## Commands

```bash
nix fmt                     # nixfmt and yamlfmt via treefmt
nix flake check             # hooks, unit checks and NixOS VM tests
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
nix develop                 # provides the scripts below
rebuild <host>              # nh os switch on the host itself
rebuild-home <home>         # home-manager switch for a standalone home
check-hosts                 # eval every host without building
```

On dullahan, skip `nix flake check`: it is too heavy. Build the touched host instead, then run targeted checks (`nix build .#checks.x86_64-linux.{pre-commit,tests-mirror,treefmt,lib}`).

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
- `tests/`: checks and VM tests, mirroring `modules/`. Shared fixtures sit in `test-support.nix` files (`flake.testSupport`).

`nixosHosts.<host>` has one option, `system`. `mkHost` in `modules/flake/nixos.nix` combines `core` with `flake.modules.nixos."nixosConfigurations/<host>"`.

## Secrets

agenix-rekey with a YubiKey master identity (`.secrets/age-yubikey-identity.pub`). Source secrets sit next to their module as `secrets/*.age`; rekeyed copies live in `.secrets/<host>` and `.secrets/homes/<home>`. `git add` a new `.age` before `agenix rekey`, or Nix cannot see it.

## Deploys

puca, leprechaun and bananach auto-upgrade daily from the `deployed` branch, staggered an hour apart (`modules/nixos/core/update.nix`). CI fast-forwards `deployed` after every host builds on `main`. Desktops deploy by hand.

## Conventions

- `pipe-operators` is enabled; statix cannot parse it, so affected files sit in its ignore list in `modules/flake/checks.nix`.
- npm-sourced pi extensions are pinned in `modules/home/core/cli/ai/pi/npm/package.json`; Renovate bumps them and the lockfile. To add one, add it there, run `npm install --package-lock-only --ignore-scripts` in that directory (its `.npmrc` pins the public registry and skips peers), then build it with `flake.lib.mkPiExtension pkgs "<name>" { }`. The `pi-extensions-<home>` checks load every extension in headless pi.
- Container images carry a `# renovate: datasource=docker depName=...` comment on the line above `image =`, or Renovate never updates them.
- Every public nginx vhost needs a `flake.monitoringChecks` entry or a `blizzard.monitoring.exempt` entry; the build fails otherwise.
- Tests for `modules/<path>/<name>` live in `tests/<path>/<name>-tests.nix`, with their helper files beside them. The `tests-mirror` check fails on a test with no matching module, and on helper files with no test beside them. Checks generated per host from host configs (`hyprland-<host>`) stay in `modules/flake/`. Package source keeps its language-native tests (aqua-booking's pytest suite).
- Never ssh to a host without the owner's approval.
