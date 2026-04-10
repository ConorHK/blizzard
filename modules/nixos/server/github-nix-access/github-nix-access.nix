{
  flake.modules.nixos.github-nix-access =
    { config, lib, ... }:
    {
      age.secrets.github-nix-token = {
        rekeyFile = ./secrets/github-nix-token.age;
      };

      nix.extraOptions = ''
        !include ${config.age.secrets.github-nix-token.path}
      '';

      # Only require the agenix service when sysusers is enabled; without it,
      # agenix uses activation scripts which run before nix-daemon on boot.
      systemd.services.nix-daemon = lib.mkIf config.systemd.sysusers.enable {
        after = [ "agenix-install-secrets.service" ];
        requires = [ "agenix-install-secrets.service" ];
      };
    };
}
