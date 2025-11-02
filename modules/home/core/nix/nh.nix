{
  flake.modules.homeManager.nh =
    { lib, config, ... }:
    {
      programs.nh = {
        enable = true;

        flake = lib.mkDefault "${config.home.homeDirectory}/repositories/blizzard";
      };
    };
}
