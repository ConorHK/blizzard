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
        statix =
          let
            # statix can't parse pipe operators or flake input repeated-key patterns
            ignored = [
              "flake.nix"
              "templates/*"
              "modules/home/core/cli/ssh.nix"
              "modules/home/desktop/media/gfx.nix"
              "modules/nixos/core/network/network-manager.nix"
              "modules/nixos/desktop/wayland/default.nix"
            ];
            configDir = pkgs.runCommand "statix-config" { } ''
              mkdir -p $out
              cat > $out/statix.toml <<EOF
              disabled = []
              nix_version = "2_4"
              ignore = [${pkgs.lib.concatMapStringsSep ", " (p: ''"${p}"'') ignored}]
              EOF
            '';
            wrapper = pkgs.writeShellScript "statix-check" ''
              exec ${pkgs.lib.getExe pkgs.statix} check --config ${configDir}/statix.toml
            '';
          in
          {
            enable = true;
            entry = toString wrapper;
            pass_filenames = false;
            files = "\\.nix$";
          };
        treefmt.enable = true;
      };
    };
}
