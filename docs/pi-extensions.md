# Pi extensions

Pi extensions come from two places.

- npm packages, pinned in one lockfile and built by Nix without running
  npm.
- Local extensions in the repo (`advisor/`, `checkpoint/`, `ogham/`, `ttsr/`, and
  single `.ts` files), built as flake packages or used as plain paths.

## npm packages

```
npm/package.json + npm/package-lock.json
        | mkPiExtension pkgs "<name>" { }
        v
store path in npm layout -> programs.pi.settings.packages
```

### The pin

[`modules/home/core/cli/ai/pi/npm/package.json`](../modules/home/core/cli/ai/pi/npm/package.json)
lists every npm extension. `package-lock.json` beside it holds the full
dependency tree, with tarball URLs and integrity hashes. Its
[`.npmrc`](../modules/home/core/cli/ai/pi/npm/.npmrc) pins the public
registry and sets `legacy-peer-deps`, because pi supplies its own peers at
runtime.

### The builder

`flake.lib.mkPiExtension` in
[`npm.nix`](../modules/home/core/cli/ai/pi/npm.nix) reads the lockfile at
eval time and:

1. Walks the dependency closure from `node_modules/<name>`, resolving each
   dependency the way npm does, from the nearest `node_modules` upward.
2. Drops `@earendil-works/*` packages, which pi provides, plus anything in
   `prune`.
3. Drops optional dependencies for other platforms (os, cpu, libc).
4. Fetches each tarball with `fetchurl` using the lockfile's integrity hash,
   then unpacks it into the npm layout under `$out`.

No npm runs at build time. The lockfile's integrity values serve as the
hashes, so there are no extra hashes to maintain.

It fails eval in two cases.

- When `package.json` and the lockfile disagree, with "pi-extensions lock
  is stale".
- When two packages land at one path. Re-nest one by hand.

Extra arguments pass through to `mkDerivation`. Use that for native
modules. [`pi-hermes-memory.nix`](../modules/home/core/cli/ai/pi/pi-hermes-memory.nix)
keeps one `better-sqlite3` prebuild and runs `autoPatchelfHook` on Linux.

### Add one

1. Add it to `npm/package.json` with a pinned version.
2. In `modules/home/core/cli/ai/pi/npm/`, run
   `npm install --package-lock-only --ignore-scripts`.
3. Create `pi-<name>.nix` from a copy of
   [`pi-ask-user.nix`](../modules/home/core/cli/ai/pi/pi-ask-user.nix).
   Build with `mkPiExtension pkgs "<name>" { }`, add an enable option, and
   append the result to `programs.pi.settings.packages`.
4. Build `.#checks.x86_64-linux.pi-extensions-<home>`.

### Updates

Renovate bumps `package.json` and the lockfile in one grouped "pi
extensions" PR, with pinned versions ([`renovate.json`](../renovate.json)).
CI runs the load checks on the PR.

## Local extensions

These live as source in
[`modules/home/core/cli/ai/pi/`](../modules/home/core/cli/ai/pi/). Two
shapes exist.

- Directories become a flake package (`packages.pi-checkpoint`,
  `packages.pi-ttsr`), registered through `programs.pi.extensionDirs`. See
  [`pi-checkpoint.nix`](../modules/home/core/cli/ai/pi/pi-checkpoint.nix).
- Single files go straight in, as in
  `programs.pi.extensions.bash-highlight = ./bash-highlight.ts;`
  ([`pi-bash-highlight.nix`](../modules/home/core/cli/ai/pi/pi-bash-highlight.nix)).

A local extension that needs an npm dependency can still use the builder.
[`pi-ttsr.nix`](../modules/home/core/cli/ai/pi/pi-ttsr.nix) builds
`picomatch` with `mkPiExtension`.

## The load check

[`tests/home/core/cli/ai/pi/pi-tests.nix`](../tests/home/core/cli/ai/pi/pi-tests.nix)
generates `pi-extensions-<home>` for each home. It rebuilds that home's pi
agent directory, then starts pi headless and offline with every configured
package. An extension that fails to load fails the check. That catches
upstream breakage in a Renovate PR before it reaches a desktop.
