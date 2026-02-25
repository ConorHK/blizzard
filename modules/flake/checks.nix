{ inputs, ... }:
{
  imports = [
    inputs.git-hooks-nix.flakeModule
  ];

  perSystem = _: {
    pre-commit.settings.hooks = {
      deadnix.enable = true;
      flake-checker.enable = true;
      ripsecrets.enable = true;
      shellcheck.enable = true;
      statix = {
        enable = true;
        # statix can't parse pipe operators or flake input repeated-key patterns
        settings.ignore = [
          "flake.nix"
          "templates/*"
          "modules/home/core/cli/ssh.nix"
          "modules/home/desktop/media/gfx.nix"
          "modules/nixos/core/network/network-manager.nix"
          "modules/nixos/desktop/android.nix"
          "modules/nixos/desktop/wayland/default.nix"
        ];
      };
      treefmt.enable = true;
    };
  };
}
