{ config, ... }:
{
  hyprland.lua.kitty = ''
    hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm app -- kitty"))
  '';

  flake.modules.homeManager.kitty = {
    imports = [ config.flake.wrappers.kitty.install ];
    wrappers.kitty.enable = true;

    # kitty.conf turns off kitty's own injection, since zmx-open hides the shell from it.
    programs = {
      fish.interactiveShellInit = ''
        if set -q KITTY_INSTALLATION_DIR
          set --global KITTY_SHELL_INTEGRATION no-rc
          source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
          set --prepend fish_complete_path "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_completions.d"
        end
      '';
      bash.initExtra = ''
        if test -n "$KITTY_INSTALLATION_DIR"; then
          export KITTY_SHELL_INTEGRATION="no-rc"
          source "$KITTY_INSTALLATION_DIR/shell-integration/bash/kitty.bash"
        fi
      '';
      zsh.initContent = ''
        if test -n "$KITTY_INSTALLATION_DIR"; then
          export KITTY_SHELL_INTEGRATION="no-rc"
          autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
          kitty-integration
          unfunction kitty-integration
        fi
      '';
    };
  };
}
