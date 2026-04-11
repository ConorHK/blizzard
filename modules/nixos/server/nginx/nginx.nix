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

      age.secrets.namecheap-acme = {
        rekeyFile = ./secrets/namecheap-acme.age;
        # acme user needs to read this to call the Namecheap API
        group = "acme";
        mode = "0440";
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = "admin@goosebox.org";
        certs = lib.mapAttrs (_: _: {
          dnsProvider = "namecheap";
          credentialsFile = config.age.secrets.namecheap-acme.path;
          webroot = null;
        }) acmeVhosts;
      };

      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
        recommendedProxySettings = true;
      };
    };
}
