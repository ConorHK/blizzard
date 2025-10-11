{
  flake.modules.homeManager.nh =
    { lib, config, ... }:
    {
      programs.nh = {
        enable = true;

        flake = lib.mkDefault "${config.home.homeDirectory}/repositories/blizzard";

        clean = {
          enable = true;

          dates = "daily";
          extraArgs = "--keep 1 --keep-since 8d";
        };
      };
    };
}
