{
  flake.modules.nixos.cachix =
    { pkgs, ... }:
    {
      # TODO use the secret
      age.secrets.cachix.rekeyFile = ./secrets/cachix.age;
      environment.systemPackages = [
        pkgs.cachix
      ];
    };
}
