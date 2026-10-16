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

      networking = {
        hostName = "bananach";
        # tailscale0 is trusted, so nginx needs no open port.
        firewall.allowedTCPPorts = lib.mkForce [ ];
      };

      blizzard = {
        # No LAN address and no open ports, so the tailnet is its only route in.
        tailscaleSsh = true;
        # gatus cannot usefully page about its own UI being down.
        monitoring.exempt = [ "monitor.goosebox.org" ];
      };

      services = {
        gatus.settings.web.address = "100.96.40.127";
        # Served here so it outlives leprechaun's nginx.
        nginx.virtualHosts."monitor.goosebox.org" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://100.96.40.127:8080";
            proxyWebsockets = true;
          };
        };
        # Reachable on tailscale0 only; the firewall stays shut on every other interface.
        openssh.openFirewall = false;
      };

      # Bind before tailscale assigns the address.
      boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
      programs.mosh.enable = false;

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
