_: {
  flake.modules.nixos.nginx =
    { config, lib, ... }:
    let
      # security.acme.defaults.dnsProvider doesn't propagate to individual certs,
      # so we derive the cert list from nginx vhosts and set dnsProvider explicitly.
      acmeVhosts = lib.filterAttrs (_: vhost: vhost.enableACME) config.services.nginx.virtualHosts;
    in
    {
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
          # deSEC caches NXDOMAIN for an hour.
          extraLegoFlags = [ "--dns.propagation.disable-rns" ];
          credentialFiles.DESEC_TOKEN_FILE = config.age.secrets.desec-acme-token.path;
        }) acmeVhosts;
      };

      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
        virtualHosts."_" = {
          default = true;
          locations."/".return = "444";
        };
      };
    };
}
