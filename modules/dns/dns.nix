{
  perSystem =
    { lib, pkgs, ... }:
    let
      # Tailnet addresses.
      leprechaun = "100.91.205.65";
      server = "100.66.244.36";

      a = value: {
        type = "A";
        inherit value;
      };

      zones."goosebox.org." = {
        "" = [
          (a server)
          {
            type = "MX";
            values = [
              {
                preference = 1;
                exchange = "mx1.simplelogin.co.";
              }
              {
                preference = 2;
                exchange = "mx2.simplelogin.co.";
              }
            ];
          }
          {
            type = "TXT";
            values = [
              "v=spf1 include:simplelogin.co ~all"
              "sl-verification=buxbjydlcokbwpagrcjvktuhwtyeec"
            ];
          }
        ];
        "*" = a server;
        "*.lep" = a leprechaun;
        calibre = a leprechaun;
        matrix = a leprechaun;
        monitor = a leprechaun;
        search = a leprechaun;
        shelfmark = a leprechaun;
        # octoDNS rejects unescaped semicolons.
        _dmarc = {
          type = "TXT";
          value = "v=DMARC1\\; p=quarantine\\; pct=100\\; adkim=s\\; aspf=s";
        };
        # Bluesky handle.
        _atproto = {
          type = "TXT";
          value = "did=did:plc:e6nqnmpbh6aox2527gpzx54t";
        };
        # Resend sending domain.
        "resend._domainkey.email" = {
          type = "TXT";
          value = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDbacKYvyC1EGjzPun8TAOlSokXjAps/JihCVFQKY75BZZKA3HJfcCFFjSgJJIiBRMXX+elCcYJ1zoDzN8ZB+kU7Tj/4wUnBOLUmZo1wHE0M1JK4kTjunERsQyVyfH6khw45rtjgm3Fy983NqSGFFFv+TJhXC+r17LEAzOg9GBZpQIDAQAB";
        };
        "send.email" = [
          {
            type = "MX";
            value = {
              preference = 10;
              exchange = "feedback-smtp.eu-west-1.amazonses.com.";
            };
          }
          {
            type = "TXT";
            value = "v=spf1 include:amazonses.com ~all";
          }
        ];
      }
      // lib.listToAttrs (
        map
          (
            key:
            lib.nameValuePair "${key}._domainkey" {
              type = "CNAME";
              value = "${key}._domainkey.simplelogin.co.";
            }
          )
          [
            "dkim"
            "dkim02"
            "dkim03"
          ]
      );

      zoneDir = pkgs.linkFarm "octodns-zones" (
        lib.mapAttrsToList (zone: records: {
          name = "${zone}yaml";
          path = pkgs.writeText "${zone}yaml" (builtins.toJSON records);
        }) zones
      );

      config = pkgs.writeText "octodns.yaml" (
        builtins.toJSON {
          providers = {
            nix = {
              class = "octodns.provider.yaml.YamlProvider";
              directory = zoneDir;
              # toJSON sorts keys, not naturally.
              enforce_order = false;
            };
            desec = {
              class = "octodns_desec.DesecProvider";
              token = "env/DESEC_TOKEN"; # pragma: allowlist secret
            };
          };
          zones = builtins.mapAttrs (_: _: {
            sources = [ "nix" ];
            targets = [ "desec" ];
          }) zones;
        }
      );

      octodns = pkgs.octodns.withProviders (_: [ pkgs.octodns-providers.desec ]);
    in
    {
      packages.dns-sync = pkgs.writeShellApplication {
        name = "dns-sync";
        runtimeInputs = [
          octodns
          pkgs.age
          pkgs.age-plugin-yubikey
        ];
        text = ''
          root=$(git rev-parse --show-toplevel)
          DESEC_TOKEN=$(age -d -i "$root/.secrets/age-yubikey-identity.pub" \
            "$root/modules/dns/secrets/desec-token.age")
          export DESEC_TOKEN
          # Dry run unless --doit is passed.
          octodns-sync --config-file ${config} "$@"
        '';
      };
    };
}
