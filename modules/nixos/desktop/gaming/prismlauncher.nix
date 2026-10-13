{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      home-manager.sharedModules = [
        {
          home.packages = [ pkgs.prismlauncher ];
        }
      ];
    };
}
