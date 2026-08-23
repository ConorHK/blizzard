{
  flake.modules.nixos."nixosConfigurations/bananach" =
    { config, lib, ... }:
    let
      fw = config.networking.firewall;
      surfaces = [
        {
          name = "firewall";
          value = fw;
        }
      ]
      ++ lib.mapAttrsToList (name: value: { inherit name value; }) fw.interfaces;
      openedOn =
        surface:
        let
          n = surface.value;
        in
        map (port: "${surface.name}:${toString port}") (n.allowedTCPPorts ++ n.allowedUDPPorts)
        ++ map (r: "${surface.name}:${toString r.from}-${toString r.to}") (
          n.allowedTCPPortRanges ++ n.allowedUDPPortRanges
        );
      opened = lib.concatMap openedOn surfaces;
    in
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMum5X2fPLL5xXfKkpmJ9MtNwyhxqsgB72wcp8t+i4MR";

      networking.hostName = "bananach";

      # No LAN address and no open ports, so the tailnet is its only route in.
      blizzard.tailscaleSsh = true;

      services.gatus.settings.web.address = "100.96.40.127";
      programs.mosh.enable = false;

      # Reachable on tailscale0 only; the firewall stays shut on every other interface.
      services.openssh.openFirewall = false;

      assertions = [
        {
          assertion = opened == [ ];
          message = "bananach is reachable on tailscale0 only, but the firewall opens ${lib.concatStringsSep ", " opened}";
        }
      ];

      system = {
        stateVersion = "25.05";
      };
    };
}
