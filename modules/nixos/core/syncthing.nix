{
  flake.modules.nixos.syncthing = {
    # configured in home module

    networking.firewall.allowedUDPPorts = [
      22000
      21027
    ];
    networking.firewall.allowedTCPPorts = [ 22000 ];
  };
}
