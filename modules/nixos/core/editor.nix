{
  flake.modules.nixos.core =
    { inputs, pkgs, ... }:
    {
      environment.systemPackages = [ inputs.cnvim.packages.${pkgs.system}.nightly ];
    };
}
