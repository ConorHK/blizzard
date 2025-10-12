{
  flake.modules.nixos.core =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vim ];
    };
  flake.modules.nixos.cnvim =
    { inputs, pkgs, ... }:
    {
      environment.systemPackages = [ inputs.cnvim.packages.${pkgs.system}.nightly ];
    };
}
