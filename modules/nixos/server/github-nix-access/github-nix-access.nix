{
  flake.modules.nixos.github-nix-access =
    { config, ... }:
    {
      age.secrets.github-nix-token = {
        rekeyFile = ./secrets/github-nix-token.age;
      };

      nix.extraOptions = ''
        include ${config.age.secrets.github-nix-token.path}
      '';

      systemd.services.nix-daemon = {
        after = [ "agenix.service" ];
        requires = [ "agenix.service" ];
      };
    };
}
