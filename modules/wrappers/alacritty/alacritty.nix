{
  flake.wrappers.alacritty =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.alacritty;
      flags."--config-file" = ./alacritty.toml;
    };
}
