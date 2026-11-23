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

## A program with a config directory

[`kitty/`](../modules/wrappers/kitty/) carries a whole directory, because
kitty looks for kittens, watchers and `open-actions.conf` beside
`kitty.conf`. The wrapper builds that directory and sets
`KITTY_CONFIG_DIRECTORY`. An environment variable reaches every entry point;
a flag would break `kitty +kitten` and `kitty @`, whose first argument must
come first.

A host adds its own lines after the shared file:

```nix
wrappers.kitty.extraConfig = ''
  font_size 14
'';
```

On macOS the Dock and Spotlight start the app bundle's executable, not
`bin/kitty`. The wrapper wraps that executable too, through
`wrapperVariants`.

Kitty reads its config at start, so a running kitty keeps the old config
until it restarts.

## A program hosts extend

[`git/`](../modules/wrappers/git/) and
[`jujutsu/`](../modules/wrappers/jujutsu/) take `extraConfig` as kitty does,
for a host's identity and defaults:

```nix
wrappers.git.extraConfig = ''
  [user]
  	email = me@example.com
'';
```

git reads the lines after the shared config, so a later value wins. A TOML
table cannot be defined twice, so jujutsu reads them as a second file.

git finds its config through `GIT_CONFIG_GLOBAL`, which only the wrapped
`git` sets. A script that needs the config calls
`config.wrappers.git.wrapper`, as [`ogham.nix`](../modules/home/core/ogham/ogham.nix)
does. A program that brings its own git reads no global config.

## A program whose config is chosen at run time

[`starship/`](../modules/wrappers/starship/) carries two prompts. fish
points `STARSHIP_CONFIG` at the jj one inside a jj repo, so the wrapper sets
the variable with `envDefault` and exposes the directory as
`config.wrappers.starship.wrapper.configDir`.

## A config that names a store path

[`zellij/`](../modules/wrappers/zellij/) loads a plugin built by this
flake. `config.kdl` holds `@autolock@` in its place, and `pkgs.replaceVars`
fills it in when the wrapper builds.

## A program with a theme

[`bat/`](../modules/wrappers/bat/) keeps its colours in a theme file,
`config/themes/blizzard.tmTheme`, beside `config/config`. Bat loads themes
from a compiled cache, never from the theme file. The wrapper builds that
cache and sets `BAT_CACHE_PATH` beside `BAT_CONFIG_DIR`.

The cache sits in the store, so `bat cache --build` cannot change it. A new
theme or syntax goes in `config/`.

The theme repeats the colours of
[`colorscheme.nix`](../modules/theme/colorscheme.nix). Change both together.

## A program that takes its config as a flag

[`btop/`](../modules/wrappers/btop/) reads no environment variable for its
config, so the wrapper passes `--config` and `--themes-dir` through `flags`.

[`mpv/`](../modules/wrappers/mpv/) only accepts `--flag=value`, which
`flagSeparator = "="` produces. The wrapper includes `mpv.conf` and leaves
the config directory alone, because mpv writes its watch-later state there.
nixpkgs points `umpv`, and on macOS the app bundle, at its own mpv. Each
gets a wrapper variant, so every way in reads the config.

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

How the test sees the config depends on the program:

- A program with a batch mode prints it. bat colours a file; kitty and mpv
  run a probe script.
- A terminal program draws it. `flake.testSupport.ptyExpect` runs fzf and
  btop in a pty and waits for a colour from the config.
- A GTK program runs on GTK's broadway display server, which needs no
  screen. zathura's debug log then names the file it read and any line it
  rejected.
- A program with no display to borrow has its own tool read the file the
  wrapper passes. alacritty's `migrate --dry-run` parses it.

Three things change when config moves into the wrapper:

- The config rides with the wrapped binary. An alias or script that calls
  the plain nixpkgs binary by store path skips it.
- Stylix themes a program through its Home Manager target. A wrapped
  program needs its colours in the config file, and its target removed from
  [`stylix.nix`](../modules/theme/stylix.nix).
- Session variables, shell aliases, shell integration and user services are
  not part of a wrapper. They stay in the Home Manager module.
  [`fzf.nix`](../modules/home/core/cli/fzf.nix) sources fzf's key bindings
  from the wrapped package.

## Config a wrapper cannot carry

Some config is read from a fixed path by more than one program. scp, sftp,
rsync and nix all read ssh's config, and none of them start a wrapped `ssh`.
On NixOS that config goes in the system file instead:
[`ssh-client.nix`](../modules/nixos/desktop/ssh-client.nix) writes the host
aliases to `/etc/ssh/ssh_config`, under `Match localuser` so root and service
accounts keep the stock settings.
