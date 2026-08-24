{
  flake.modules.homeManager.laptop = {
    programs.waybar.extraModules = [ "battery" ];
  };
}
