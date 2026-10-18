# Host composition

Every `.nix` file under `modules/` and `tests/` is a flake-parts module,
loaded by [import-tree](https://github.com/vic/import-tree) from
[`flake.nix`](../flake.nix). No import list exists. Files contribute to
shared attributes, and the host builders read those attributes.

## Modules are named, not imported

A file publishes a NixOS module under a name:

```nix
flake.modules.nixos.duckdns = { config, pkgs, ... }: { ... };
```

Defining a module does nothing on its own. A host must pick it. Several
files can add to one name; the module system merges them. Every
`flake.modules.homeManager.pi` definition under
`modules/home/core/cli/ai/pi/` merges into one `pi` module.

## Building a NixOS host

`mkHost` in [`modules/flake/nixos.nix`](../modules/flake/nixos.nix) builds
each entry in `nixosHosts` from two modules:

1. `flake.modules.nixos.core`, the baseline every host gets
   ([`modules/nixos/core/imports.nix`](../modules/nixos/core/imports.nix)):
   agenix, alerts, network, nix settings, auto-upgrade, ZFS alerts, and more.
2. `flake.modules.nixos."nixosConfigurations/<host>"`, which collects
   everything specific to that host.

It also passes three specialArgs: `inputs`, `blizzardLib` (the
`flake.lib` helpers), and `monitoringChecks` (see
[monitoring.md](monitoring.md)).

## A host directory

Each file in `modules/hosts/<host>/` adds to the same
`"nixosConfigurations/<host>"` module:

| File | Adds |
|---|---|
| `imports.nix` | Registers `nixosHosts.<host>`, picks opt-in modules, declares host checks |
| `configuration.nix` | Hostname, address, `age.rekey.hostPubkey`, `blizzard.*` settings |
| `hardware.nix` | Kernel, boot, and `facter.reportPath = ./facter.json` |
| `facter.json` | Hardware report from nixos-facter; drives driver and firmware choices |
| `disko.nix` | Disk layout, usually `config.flake.lib.mkDisko { }` |
| `home.nix` | Optional standalone Home Manager config (desktops only) |

[`puca/imports.nix`](../modules/hosts/puca/imports.nix) is the smallest
example:

```nix
nixosHosts.puca = { };
flake.modules.nixos."nixosConfigurations/puca".imports = with config.flake.modules.nixos; [
  bluetooth
  github-nix-access
  grub-boot
  home-assistant
  server-users
];
```

`nixosHosts.<host>` has one option, `system` (default `x86_64-linux`).

## Homes are standalone

Home Manager does not run as a NixOS module here.
[`standalone-homes.nix`](../modules/flake/standalone-homes.nix) builds each
`homeConfigurations.<name>` entry from:

1. `flake.modules.homeManager.core`
2. `flake.modules.homeManager.theme`, if defined
3. `flake.modules.homeManager."homeConfigurations/<name>"`, from the host's
   `home.nix`

So `rebuild <host>` and `rebuild-home <home>` deploy separately. A home
change never needs a system switch.

`standalone-homes.nix` also exports itself as
`flakeModules.homeConfigurations`, so other flakes can reuse the home
builder.

## Add a host

1. Create `modules/hosts/<host>/` with `imports.nix`, `configuration.nix`,
   `hardware.nix`, `disko.nix`.
2. Generate `facter.json` on the machine with `nixos-facter`.
3. Set `age.rekey.hostPubkey` and run `agenix rekey` (see
   [secrets.md](secrets.md)).
4. Run `check-hosts` to evaluate every host.

CI picks up the new host from `nixosConfigurations` on its own (see
[deploy.md](deploy.md)). Servers auto-upgrade by default; set
`system.autoUpgrade.enable = false` for a desktop.

## Add an opt-in module

1. Create `modules/nixos/server/<name>.nix` defining
   `flake.modules.nixos.<name>`.
2. Add `<name>` to the host's `imports.nix` list.
3. Add a test at `tests/nixos/server/<name>-tests.nix` if it has logic
   worth testing. `tests-mirror` requires the paths to match.
