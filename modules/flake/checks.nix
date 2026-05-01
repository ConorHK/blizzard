{ inputs, ... }:
{
  imports = [
    inputs.git-hooks-nix.flakeModule
  ];

  perSystem =
    { pkgs, ... }:
    {
      pre-commit.settings.hooks = {
        deadnix.enable = true;
        flake-checker = {
          enable = true;
          entry =
            let
              wrapper = pkgs.writeShellScript "flake-checker" ''
                NIX_FLAKE_CHECKER_CHECK_OWNER=false ${pkgs.lib.getExe pkgs.flake-checker} -f
              '';
            in
            toString wrapper;
          pass_filenames = false;
        };
        yamllint.enable = true;
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
