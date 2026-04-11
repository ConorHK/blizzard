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

      age.secrets.namecheap-api-user = {
        rekeyFile = ./secrets/namecheap-api-user.age;
        group = "acme";
        mode = "0440";
      };

      age.secrets.namecheap-api-key = {
        rekeyFile = ./secrets/namecheap-api-key.age;
        group = "acme";
        mode = "0440";
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@goosebox.org";
        certs = lib.mapAttrs (_: _: {
          dnsProvider = "namecheap";
          webroot = null;
          credentialFiles = {
            "NAMECHEAP_API_USER_FILE" = config.age.secrets.namecheap-api-user.path;
            "NAMECHEAP_API_KEY_FILE" = config.age.secrets.namecheap-api-key.path;
          };
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
