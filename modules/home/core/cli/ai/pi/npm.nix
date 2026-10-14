{ lib, ... }:
let
  # Renovate keeps ./npm/package-lock.json current.
  entries = (lib.importJSON ./npm/package-lock.json).packages;
  wanted = (lib.importJSON ./npm/package.json).dependencies;

  parentOf =
    path:
    let
      parts = lib.splitString "/node_modules/" (lib.removePrefix "node_modules/" path);
    in
    if lib.length parts == 1 then
      ""
    else
      "node_modules/" + lib.concatStringsSep "/node_modules/" (lib.init parts);

  # npm's lookup: nearest node_modules upward.
  resolve =
    from: dep:
    let
      candidate = lib.optionalString (from != "") "${from}/" + "node_modules/${dep}";
    in
    if entries ? ${candidate} then
      candidate
    else if from == "" then
      null
    else
      resolve (parentOf from) dep;
in
{
  # Self-contained extension dir, npm layout.
  flake.lib.mkPiExtension =
    pkgs: name:
    {
      # Deps the package never loads here.
      prune ? [ ],
      stdenv ? pkgs.stdenvNoCC,
      ...
    }@args:
    let
      platform = pkgs.stdenv.hostPlatform;
      os = if platform.isDarwin then "darwin" else "linux";
      cpu = if platform.isAarch64 then "arm64" else "x64";
      libc = if platform.isMusl then "musl" else "glibc";
      allows =
        list: value:
        list == [ ]
        || lib.elem value list
        || (lib.all (lib.hasPrefix "!") list && !lib.elem "!${value}" list);
      fits =
        entry:
        allows (entry.os or [ ]) os
        && allows (entry.cpu or [ ]) cpu
        && (platform.isDarwin || allows (entry.libc or [ ]) libc);
      # pi provides these at runtime.
      pruned = dep: lib.hasPrefix "@earendil-works/" dep || lib.elem dep prune;

      root = "node_modules/${name}";
      closure = lib.genericClosure {
        startSet = [ { key = root; } ];
        operator =
          { key }:
          let
            entry = entries.${key};
            edges =
              map (dep: {
                inherit dep;
                optional = false;
              }) (lib.attrNames (entry.dependencies or { }))
              ++ map (dep: {
                inherit dep;
                optional = true;
              }) (lib.attrNames (entry.optionalDependencies or { }));
          in
          lib.concatMap (
            { dep, optional }:
            let
              path = resolve key dep;
            in
            if pruned dep then
              [ ]
            else if path == null then
              if optional then [ ] else throw "pi-extensions lock: ${key} needs ${dep}, not in the lock"
            else if fits entries.${path} then
              [ { key = path; } ]
            else
              [ ]
          ) edges;
      };

      # Re-root under the extension.
      targetOf =
        path:
        if path == root then
          "."
        else if lib.hasPrefix "${root}/" path then
          lib.removePrefix "${root}/" path
        else
          path;
      layout = map (
        { key }:
        {
          target = targetOf key;
          tarball = pkgs.fetchurl {
            url = entries.${key}.resolved;
            hash = entries.${key}.integrity;
          };
        }
      ) closure;
      targets = map (item: item.target) layout;
    in
    # A failed lock update must not pass.
    assert lib.assertMsg (
      wanted == entries."".dependencies
    ) "pi-extensions lock is stale; rerun npm in npm/";
    assert lib.assertMsg (lib.allUnique targets)
      "pi-extensions lock: ${name} has two packages at one path; nest one by hand";
    stdenv.mkDerivation (
      {
        pname = baseNameOf name;
        inherit (entries.${root}) version;
        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
        ''
        + lib.concatMapStrings (item: ''
          mkdir -p $out/${item.target}
          tar xzf ${item.tarball} -C $out/${item.target} --strip-components=1
        '') layout
        + ''
          runHook postInstall
        '';
      }
      // removeAttrs args [
        "prune"
        "stdenv"
      ]
    );
}
