{
  flake.modules.nixos.syncthing =
    { config, lib, ... }:
    # enabled in the home module, so only open ports where a user actually runs it
    lib.mkIf
      (lib.any (user: user.services.syncthing.enable) (lib.attrValues (config.home-manager.users or { })))
      {
        networking.firewall.allowedUDPPorts = [
          22000
          21027
        ];
        networking.firewall.allowedTCPPorts = [ 22000 ];
      };
}
