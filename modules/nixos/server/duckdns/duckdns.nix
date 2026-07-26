{
  flake.modules.nixos.duckdns =
    { config, pkgs, ... }:
    let
      # The label before ".duckdns.org" (e.g. "goosebox" -> goosebox.duckdns.org).
      domain = "vpn-concave";
    in
    {
      age.secrets.duckdns-token.rekeyFile = ./secrets/duckdns-token.age;

      systemd.services.duckdns = {
        description = "Update DuckDNS record for ${domain}.duckdns.org";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          # Expose the token at $CREDENTIALS_DIRECTORY/token, kept out of argv.
          LoadCredential = "token:${config.age.secrets.duckdns-token.path}";
        };
        script = ''
          set -euo pipefail
          token="$(cat "$CREDENTIALS_DIRECTORY/token")"
          # Empty ip= => DuckDNS uses the request source IP (this host's WAN IP).
          resp="$(${pkgs.curl}/bin/curl -fsS \
            "https://www.duckdns.org/update?domains=${domain}&token=$token&ip=")"
          echo "duckdns: ${domain}.duckdns.org -> $resp"
          [ "$resp" = "OK" ]
        '';
      };

      systemd.timers.duckdns = {
        description = "Refresh DuckDNS record every 5 minutes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          Persistent = true;
        };
      };
    };
}
