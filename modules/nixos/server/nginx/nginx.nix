_: {
  flake.modules.nixos.nginx =
    { config, lib, ... }:
    let
      inherit (config.blizzard.nginx) redirects;
      # security.acme.defaults.dnsProvider doesn't propagate to individual certs,
      # so we derive the cert list from nginx vhosts and set dnsProvider explicitly.
      acmeVhosts = lib.filterAttrs (_: vhost: vhost.enableACME) config.services.nginx.virtualHosts;
    in
    {
      options.blizzard.nginx.redirects = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Old host names redirected to new ones.";
      };

      config = {
        networking.firewall.allowedTCPPorts = [
          80 # HTTP → HTTPS redirect
          443 # HTTPS
        ];

        age.secrets.desec-acme-token = {
          rekeyFile = ./secrets/desec-acme-token.age;
          group = "acme";
          mode = "0440";
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "admin@goosebox.org";
          # deSEC rate-limits writes; serialize.
          maxConcurrentRenewals = 1;
          certs = lib.mapAttrs (_: _: {
            dnsProvider = "desec";
            webroot = null;
            # MagicDNS hides fresh challenge TXTs.
            dnsResolver = "1.1.1.1:53";
            # deSEC anycast nodes sync slowly; checks race.
            extraLegoFlags = [ "--dns.propagation.wait=120s" ];
            credentialFiles.DESEC_TOKEN_FILE = config.age.secrets.desec-acme-token.path;
          }) acmeVhosts;
        };

        services.nginx = {
          enable = true;
          recommendedTlsSettings = true;
          recommendedOptimisation = true;
          recommendedGzipSettings = true;
          recommendedProxySettings = true;
          virtualHosts = {
            "_" = {
              default = true;
              locations."/".return = "444";
            };
          }
          // lib.mapAttrs (_: to: {
            enableACME = true;
            forceSSL = true;
            globalRedirect = to;
            # 308 keeps POSTs from apps intact.
            redirectCode = 308;
          }) redirects;
        };

        blizzard.monitoring.exempt = lib.attrNames redirects;
      };
    };
}
