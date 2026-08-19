{ lib, config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      waybarUsers =
        nixos:
        lib.filter (user: user.programs.waybar.enable or false) (
          lib.attrValues (nixos.config.home-manager.users or { })
        );

      hosts = lib.filterAttrs (
        _: nixos: nixos.config.nixpkgs.hostPlatform.system == system && waybarUsers nixos != [ ]
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

      packages = nixos: map (user: "${user.programs.waybar.package}") (waybarUsers nixos);
    in
    {
      checks =
        mkChecks hosts "dispatch" ./check-dispatch.sh [ pkgs.binutils ] packages
        // mkChecks hosts "commands" ./check-commands.sh [ pkgs.jq ] (
          nixos: map (user: "${user.xdg.configFile."waybar/config".source}") (waybarUsers nixos)
        )
        // mkChecks hyprlandHosts "lua-api" ./check-lua-api.sh [ pkgs.binutils ] (
          nixos: [ "${nixos.config.programs.hyprland.package}/bin/Hyprland" ] ++ packages nixos
        );
    };
}
