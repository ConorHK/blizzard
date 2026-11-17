{
  flake.wrappers.ripgrep =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.ripgrep;
      env.RIPGREP_CONFIG_PATH = ./ripgreprc;
    };
}
