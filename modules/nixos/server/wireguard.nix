{
  flake.modules.nixos.wireguard-gateway =
    { pkgs, ... }:
    let
      wgSubnet = "10.100.0.0/24";
      wgPort = 51820;
      privateKeyFile = "/var/lib/wireguard/wg0-private";
    in
    {
      # Forward phone traffic from wg0 onto the tailnet.
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      networking.firewall = {
        allowedUDPPorts = [ wgPort ];
        trustedInterfaces = [ "wg0" ];
      };

      networking.wireguard.interfaces.wg0 = {
        ips = [ "10.100.0.1/24" ];
        listenPort = wgPort;

        # Root-only key, generated on first activation. Never enters git.
        inherit privateKeyFile;
        generatePrivateKeyFile = true;

        # Masquerade wg0 traffic onto tailscale0 so tailnet peers route replies
        # back to leprechaun (no subnet-route advertisement or ACL change needed).
        # Also export the public key to a world-readable file for client config.
        postSetup = ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${wgSubnet} -o tailscale0 -j MASQUERADE
          ${pkgs.wireguard-tools}/bin/wg pubkey < ${privateKeyFile} > /var/lib/wireguard/wg0-public
          ${pkgs.coreutils}/bin/chmod 644 /var/lib/wireguard/wg0-public
        '';
        postShutdown = ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${wgSubnet} -o tailscale0 -j MASQUERADE
        '';

        peers = [
          {
            # phone (plain WireGuard, replaces the Tailscale client)
            publicKey = "pP2lrJ5n2Hm7t7gDYSSPH9jjbJdRdfaRTST+5WSPRy0="; # pragma: allowlist secret -- WireGuard public key, not sensitive
            allowedIPs = [ "10.100.0.2/32" ];
          }
        ];
      };
    };
}
