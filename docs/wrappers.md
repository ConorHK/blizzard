# Wrapped programs

A wrapped program is a package that carries its own config. The config
lives in the repo in the program's native format, and the wrapper points
the program at it. Nothing lands in `$HOME`, so the same package runs
under NixOS, Home Manager, `nix run` or `nix shell`.

```
modules/wrappers/<name>/<config file>
        | flake.wrappers.<name>
        v
packages.<system>.<name> -> bin/<program> with the config baked in
```

[nix-wrapper-modules](https://github.com/nix-community/nix-wrapper-modules)
builds the wrappers. [`modules/flake/wrappers.nix`](../modules/flake/wrappers.nix)
imports its flake-parts module.

## A wrapper directory

`modules/wrappers/<name>/` holds one `.nix` file and the config beside it.
[`ripgrep/`](../modules/wrappers/ripgrep/) is the smallest example:

```nix
flake.wrappers.ripgrep =
  { pkgs, wlib, ... }:
  {
    imports = [ wlib.modules.default ];
    package = pkgs.ripgrep;
    env.RIPGREP_CONFIG_PATH = ./ripgreprc;
  };
```

Every wrapper sets `package`. `wlib.modules.default` adds `env`,
`envDefault`, `flags` and `constructFiles`. Pass config as a path. The
library copies that one file to the store, so the wrapper rebuilds only
when the file changes.

## What a wrapper exports

| Output | Use |
|---|---|
| `packages.<system>.<name>` | The wrapped package, built with the flake's `pkgs` |
| `wrappers.<name>.wrap { inherit pkgs; ... }` | The same package with extra settings |
| `wrappers.<name>.install` | A module that installs it under NixOS or Home Manager |
| `wrapperModules.<name>` | The wrapper module itself, for another flake to extend |

## Installing a wrapper

A host module imports `install` and turns the wrapper on:

```nix
{ config, ... }:
{
  flake.modules.homeManager.core = {
    imports = [ config.flake.wrappers.ripgrep.install ];
    wrappers.ripgrep.enable = true;
  };
}
```

`install` adds the package to `home.packages` under Home Manager and to
`environment.systemPackages` under NixOS. It builds with the host's `pkgs`.

One host changes a wrapper through the same option:

```nix
wrappers.ripgrep.flags."--hidden" = true;
```

`config.wrappers.<name>.wrapper` is the built package, for aliases and
other modules that call the program by store path.

## Moving a program out of Home Manager

1. Write the config in its native format in `modules/wrappers/<name>/`.
2. Define `flake.wrappers.<name>` beside it. Point the program at the
   config with a flag or an environment variable.
3. Replace the `programs.<name>` block in the Home Manager module with the
   `install` import. Keep the module name, so downstream flakes still
   import it.
4. Add `tests/wrappers/<name>/<name>-tests.nix`. Run the wrapped program
   and assert on behaviour the config causes.

Three things change when config moves into the wrapper:

- The config rides with the wrapped binary. An alias or script that calls
  the plain nixpkgs binary by store path skips it.
- Stylix themes a program through its Home Manager target. A wrapped
  program needs its colours in the config file, and its target removed from
  [`stylix.nix`](../modules/theme/stylix.nix).
- Session variables, shell aliases and user services are not part of a
  wrapper. They stay in the Home Manager module.
