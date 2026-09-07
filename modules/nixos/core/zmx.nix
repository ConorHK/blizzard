{
  flake.modules.nixos.zmx =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.zmx ];
    };
}
