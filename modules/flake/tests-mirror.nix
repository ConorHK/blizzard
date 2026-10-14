{ lib, ... }:
let
  testsRoot = ../../tests;
  modulesRoot = ../../modules;

  relative = file: lib.removePrefix "${toString testsRoot}/" (toString file);
  inModules = dir: if dir == "." then modulesRoot else modulesRoot + "/${dir}";

  # <name>-tests.nix needs a sibling <name> or <name>.*.
  covers =
    rel:
    let
      dir = dirOf rel;
      name = lib.removeSuffix "-tests.nix" (baseNameOf rel);
      entries = lib.attrNames (builtins.readDir (inModules dir));
    in
    if !builtins.pathExists (inModules dir) then
      false
    else if lib.hasSuffix "-tests.nix" rel then
      lib.any (entry: entry == name || lib.hasPrefix "${name}." entry) entries
    else
      true;

  orphans = lib.filter (rel: !covers rel) (
    map relative (lib.filesystem.listFilesRecursive testsRoot)
  );
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.tests-mirror = pkgs.runCommand "tests-mirror" { } (
        if orphans == [ ] then
          "touch $out"
        else
          ''
            echo "tests/ entries with no matching modules/ path:"
            printf '  %s\n' ${lib.escapeShellArgs orphans}
            exit 1
          ''
      );
    };
}
