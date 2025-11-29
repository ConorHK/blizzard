{
  flake.modules.nixos.cachix =
    { pkgs, ... }:
    {
      # Use secret in cachix auth
      age.secrets.cachix.rekeyFile = ./secrets/cachix.age;
      environment.systemPackages = [
        pkgs.cachix
      ];
    };
}
