{
  flake.modules.homeManager.core =
    { config, ... }:
    {
      programs.bash = {
        enable = true;
        # Login shells get vars via ~/.profile; interactive-only shells
        # (zellij panes) read this instead.
        initExtra = ''. "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"'';
      };
    };
}
