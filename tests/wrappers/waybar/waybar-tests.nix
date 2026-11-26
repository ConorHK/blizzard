{ lib, config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      hosts = lib.filterAttrs (
        _: nixos:
        nixos.config.nixpkgs.hostPlatform.system == system && (nixos.config.wrappers.waybar.enable or false)
      ) config.flake.nixosConfigurations;

      hyprlandHosts = lib.filterAttrs (_: nixos: nixos.config.programs.hyprland.enable or false) hosts;

      mkChecks =
        hostSet: name: script: nativeBuildInputs: arguments:
        lib.mapAttrs' (
          host: nixos:
          lib.nameValuePair "waybar-${name}-${host}" (
            pkgs.runCommand "waybar-${name}-${host}" { inherit nativeBuildInputs; } ''
              ${pkgs.writeShellScript "waybar-${name}" (builtins.readFile script)} ${lib.escapeShellArgs (arguments nixos)}
              touch $out
            ''
          )
        ) hostSet;

      packages = nixos: [ "${nixos.config.wrappers.waybar.package}" ];

      check-backups = pkgs.writeShellApplication {
        name = "check-backups";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
        ];
        text = builtins.readFile ../../../modules/wrappers/waybar/check-backups.sh;
      };

      check-flake-updates = pkgs.writeShellApplication {
        name = "check-flake-updates";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.jujutsu
        ];
        bashOptions = [ ];
        text = builtins.readFile ../../../modules/wrappers/waybar/check-flake-updates.sh;
      };
    in
    {
      checks = {
        waybar-backups = pkgs.runCommand "waybar-backups" { nativeBuildInputs = [ pkgs.jq ]; } ''
          ${pkgs.writeShellScript "check-backups-tests" (builtins.readFile ./check-backups-tests.sh)} ${lib.getExe check-backups}
          touch $out
        '';
        waybar-flake-updates =
          pkgs.runCommand "waybar-flake-updates"
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
      // mkChecks hosts "commands" ./check-commands.sh [ pkgs.jq ] (nixos: [
        "${nixos.config.wrappers.waybar.flags."--config".data}"
      ])
      // mkChecks hyprlandHosts "lua-api" ./check-lua-api.sh [ pkgs.binutils ] (
        nixos: [ "${nixos.config.programs.hyprland.package}/bin/Hyprland" ] ++ packages nixos
      );
    };
}
