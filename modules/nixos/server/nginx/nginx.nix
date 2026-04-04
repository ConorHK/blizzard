_: {
  flake.modules.nixos.nginx =
    { config, ... }:
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
        defaults = {
          email = "admin@goosebox.org";
          dnsProvider = "namecheap";
          # File contains NAMECHEAP_API_USER and NAMECHEAP_API_KEY
          credentialsFile = config.age.secrets.namecheap-acme.path;
        };
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
