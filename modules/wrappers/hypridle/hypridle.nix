{
  flake.wrappers.hypridle =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.hypridle;
      flags."--config" = ./hypridle.conf;
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.hypridle = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
