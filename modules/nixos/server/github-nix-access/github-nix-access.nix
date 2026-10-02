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

      # agenix installs via a unit here.
      systemd.services.nix-daemon =
        lib.mkIf (config.systemd.sysusers.enable || config.services.userborn.enable)
          {
            after = [ "agenix-install-secrets.service" ];
            wants = [ "agenix-install-secrets.service" ];
          };
    };
}
