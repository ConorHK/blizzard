{
  flake.wrappers.fzf =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.fzf;
      env.FZF_DEFAULT_OPTS_FILE = ./fzfrc;
    };
}
