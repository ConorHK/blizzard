{ lib, ... }:
let
  testsRoot = ../../tests;
  modulesRoot = ../../modules;

  relative = file: lib.removePrefix "${toString testsRoot}/" (toString file);
  inModules = dir: if dir == "." then modulesRoot else modulesRoot + "/${dir}";

  inTests = dir: if dir == "." then testsRoot else testsRoot + "/${dir}";
  listing = root: dir: lib.attrNames (builtins.readDir (root dir));

  # <name>-tests.nix needs a sibling <name> or <name>.*.
  # Helpers need a test beside them.
  covers =
    rel:
    let
      dir = dirOf rel;
      file = baseNameOf rel;
      name = lib.removeSuffix "-tests.nix" file;
    in
    if !builtins.pathExists (inModules dir) then
      false
    else if lib.hasSuffix "-tests.nix" file then
      lib.any (entry: entry == name || lib.hasPrefix "${name}." entry) (listing inModules dir)
    else if file == "test-support.nix" then
      true
    else if lib.hasSuffix ".nix" file then
      false
    else
      lib.any (lib.hasSuffix "-tests.nix") (listing inTests dir);

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
            echo "tests/ files with no matching module or test:"
            printf '  %s\n' ${lib.escapeShellArgs orphans}
            exit 1
          ''
      );
    };
}
