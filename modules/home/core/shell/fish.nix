{
  flake.modules.homeManager.core =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables.SHELLS = lib.getExe pkgs.fish;
        shell.enableFishIntegration = true;
      };
      xdg.configFile."zellij/config.kdl".text = lib.concatStringsSep "\n" [
        ''
          default_shell "fish"
        ''
      ];
      programs = {
        zoxide.enableFishIntegration = true;
        carapace = {
          enable = true;
          enableFishIntegration = true;
        };
        fish = {
          enable = true;
          functions = {
            fish_greeting = "";
          };
          interactiveShellInit = ''
            # vim mode
            fish_vi_key_bindings
            set fish_cursor_default     block      blink
            set fish_cursor_insert      line       blink
            set fish_cursor_replace_one underscore blink
            set fish_cursor_visual      block

            # Alduin-based fish colors
            set fish_color_normal dfdfaf
            set fish_color_command 87875f        # green
            set fish_color_param dfdfaf          # fg
            set fish_color_error 8b5f61          # red
            set fish_color_comment 878787        # cyan
            set fish_color_quote fed975          # yellow
            set fish_color_redirection dfdfaf    # fg
            set fish_color_end 878787            # cyan/soft
            set fish_color_operator 87afaf       # blue
            set fish_color_escape af875f         # orange-ish accent
            set fish_color_autosuggestion 626262 # dim gray to fit bg
            set fish_color_selection 262626      # black_soft
            set fish_color_search_match d69f74   # orange
            set fish_color_valid_path 87afaf     # blue
            set fish_color_cwd 87875f            # green
            set fish_color_user dfdfaf           # fg
            set fish_color_host 87afaf           # blue
            set fish_color_host_remote af8787    # magenta
            set fish_color_cancel 8b5f61         # red
          '';
          plugins = [
            {
              name = "puffer-fish";
              inherit (pkgs.fishPlugins.puffer) src;
            }
          ];
        };
      };
    };
}
