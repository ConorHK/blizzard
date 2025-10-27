{ inputs, ... }:
{
  imports = [
    inputs.git-hooks-nix.flakeModule
  ];

  perSystem =
    { ... }:
    {
      pre-commit.settings.hooks = {
        flake-checker.enable = true;
        ripsecrets.enable = true;
        shellcheck.enable = true;
        treefmt.enable = true;
      };
    };
}
