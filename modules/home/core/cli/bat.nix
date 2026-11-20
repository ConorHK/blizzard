{ config, ... }:
{
  flake.modules.homeManager.core = {
    imports = [ config.flake.wrappers.bat.install ];
    wrappers.bat.enable = true;

    home = {
      sessionVariables = {
        MANPAGER = "bat --plain";
        PAGER = "bat --plain";
      };
      shellAliases = {
        cat = "bat --style='plain,rule,header' --paging never";
        less = "bat --plain";
      };
    };
  };
}
