{
  flake.modules.nixos.nextdns =
    { config, pkgs, ... }:
    {
      age.secrets.nextdns-profile-id.rekeyFile = ./secrets/nextdns-profile-id.age;

      systemd.services.nextdns = {
        description = "NextDNS proxy for WireGuard clients";
        # Resolves the Private DNS hostname for tunneled phones; binds to wg0.
        # requires, not just after: the listen address exists only once wg0 is up.
        after = [ "wireguard-wg0.service" ];
        requires = [ "wireguard-wg0.service" ];
        partOf = [ "wireguard-wg0.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
          CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
          LoadCredential = "profile-id:${config.age.secrets.nextdns-profile-id.path}";
          RuntimeDirectory = "nextdns";
          Restart = "on-failure";
          RestartSec = "5s";
        };
        script = ''
          exec ${pkgs.nextdns}/bin/nextdns run \
            --config "$(cat "$CREDENTIALS_DIRECTORY/profile-id")" \
            --listen 10.100.0.1:53 \
            --control /run/nextdns/nextdns.sock \
            --cache-size 10MB \
            --report-client-info=false
        '';
      };
    };
}
