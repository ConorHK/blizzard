{ lib, config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      scripts = ../../../modules/wrappers/eww/scripts;

      hosts = lib.filterAttrs (
        _: nixos:
        nixos.config.nixpkgs.hostPlatform.system == system && (nixos.config.wrappers.eww.enable or false)
      ) config.flake.nixosConfigurations;

      hyprlandHosts = lib.filterAttrs (_: nixos: nixos.config.programs.hyprland.enable or false) hosts;

      mkChecks =
        hostSet: name: script: nativeBuildInputs: arguments:
        lib.mapAttrs' (
          host: nixos:
          lib.nameValuePair "eww-${name}-${host}" (
            pkgs.runCommand "eww-${name}-${host}" { inherit nativeBuildInputs; } ''
              ${pkgs.writeShellScript "eww-${name}" (builtins.readFile script)} ${lib.escapeShellArgs (arguments nixos)}
              touch $out
            ''
          )
        ) hostSet;

      check-backups = pkgs.writeShellApplication {
        name = "check-backups";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
        ];
        text = builtins.readFile "${scripts}/check-backups.sh";
      };

      check-flake-updates = pkgs.writeShellApplication {
        name = "check-flake-updates";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jujutsu
        ];
        bashOptions = [ ];
        text = builtins.readFile "${scripts}/check-flake-updates.sh";
      };
    in
    {
      checks = {
        eww-backups = pkgs.runCommand "eww-backups" { nativeBuildInputs = [ pkgs.jq ]; } ''
          ${pkgs.writeShellScript "check-backups-tests" (builtins.readFile ./check-backups-tests.sh)} ${lib.getExe check-backups}
          touch $out
        '';
        eww-flake-updates =
          pkgs.runCommand "eww-flake-updates"
            {
              nativeBuildInputs = [
                pkgs.git
                pkgs.jq
                pkgs.jujutsu
              ];
            }
            ''
              ${pkgs.writeShellScript "check-flake-updates-tests" (builtins.readFile ./check-flake-updates-tests.sh)} ${lib.getExe check-flake-updates}
              touch $out
            '';
      }
      // mkChecks hosts "commands" ./check-commands.sh [ ] (
        nixos:
        [ nixos.config.wrappers.eww.flags."--config".data ]
        ++ map (p: toString (p.data or p)) nixos.config.wrappers.eww.runtimePkgs
      )
      // mkChecks hyprlandHosts "lua-api" ./check-lua-api.sh [ ] (nixos: [
        "${nixos.config.programs.hyprland.package}/bin/Hyprland"
        "${scripts}/sidebar-focus.sh"
      ]);
    };
}
