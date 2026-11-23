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
    in
    {
      checks = {
        waybar-backups = pkgs.runCommand "waybar-backups" { nativeBuildInputs = [ pkgs.jq ]; } ''
          ${pkgs.writeShellScript "check-backups-tests" (builtins.readFile ./check-backups-tests.sh)} ${lib.getExe check-backups}
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
