{
  # A jj workspace dialog beside Herdr's git worktree one, opened from the space menus in jj repos.
  flake.modules.homeManager.herdr =
    { config, ... }:
    {
      xdg.configFile = config.lib.herdr.modFiles "jj-workspace" ./jj-workspace;
    };
}
