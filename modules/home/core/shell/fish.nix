{
  flake.modules.homeManager.core =
    { pkgs, lib, ... }:
    let
      promptSettings = {
        custom.jj = {
          when = "jj root";
          command = ''
            jj log -r @ --no-graph --color never -T 'separate(" ", "at", change_id.shortest(4), if(empty, "(empty)"))'
          '';
          format = "[$output]($style) ";
          style = "purple";
        };
        cmd_duration = {
          format = " [⏱ $duration]($style) ";
        };
        directory = {
          read_only = " 󰌾";
        };
        fill = {
          symbol = "·";
          style = "bright-black";
        };
        git_branch = {
          symbol = "on ";
          format = "[$symbol](white)[$branch(:$remote_branch)]($style) ";
        };
        git_status = {
          format = "(([$conflicted](bright-red) )([$stashed](bright-green) )([$deleted](bright-red) )([$renamed](bright-yellow) )([$modified](bright-yellow) )([$staged](bright-yellow) )([$untracked](bright-blue) )[$ahead_behind](bright-green) )";
          conflicted = "=$count";
          ahead = "⇡$count";
          behind = "⇣$count";
          diverged = "⇡$ahead_count ⇣$behind_count";
          untracked = "?$count";
          stashed = "*$count";
          modified = "!$count";
          staged = "+$count";
          renamed = "»$count";
          deleted = "✖$count";
        };
        hostname = {
          ssh_symbol = "";
          format = "[$ssh_symbol$hostname]($style) ";
          style = "bold yellow";
        };
        kubernetes = {
          disabled = false;
          format = "[$symbol$context(/$namespace)]($style) ";
        };
        nix_shell = {
          symbol = " ";
          format = "[$symbol$name \\($state\\)]($style) ";
        };
        nodejs = {
          format = "[$symbol($version )]($style) ";
          disabled = true;
        };
        python = {
          symbol = " ";
          format = "[\${symbol}\${pyenv_prefix}(\${version} )(\($virtualenv\) )]($style) ";
        };
        status = {
          disabled = false;
          symbol = "✘";
          format = "[$symbol $status]($style) ";
        };
        time = {
          disabled = false;
          format = "[$time]($style) ";
          style = "bright-black";
        };
        username = {
          format = "[\${user}]($style) ";
        };
      };
      jjSettings = lib.recursiveUpdate promptSettings {
        format = lib.concatStrings [
          "$directory"
          "$custom" # jj change id
          "$fill"
          "$status"
          "$cmd_duration"
          "$all"
          "$line_break"
          "$character"
        ];
        git_branch.disabled = true;
        git_commit.disabled = true;
        git_state.disabled = true;
        git_metrics.disabled = true;
        git_status.disabled = true;
      };
    in
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
      xdg.configFile."starship-jj.toml".source =
        (pkgs.formats.toml { }).generate "starship-jj.toml"
          jjSettings;

      programs = {
        zsh.initExtra = "exec fish";
        zoxide.enableFishIntegration = true;
        fzf.enableFishIntegration = true;
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

            # jj prompt in jj repos, git prompt elsewhere
            function __starship_pick --on-variable PWD
                if jj root >/dev/null 2>&1
                    set -gx STARSHIP_CONFIG $HOME/.config/starship-jj.toml
                else
                    set -gx STARSHIP_CONFIG $HOME/.config/starship.toml
                end
            end
            __starship_pick
          '';
          plugins = [
            {
              name = "puffer-fish";
              inherit (pkgs.fishPlugins.puffer) src;
            }
          ];
        };

        starship = {
          enable = true;
          settings = promptSettings // {
            format = lib.concatStrings [
              "$directory"
              "$git_branch"
              "$git_commit"
              "$git_state"
              "$git_metrics"
              "$git_status"
              "$fill"
              "$status"
              "$cmd_duration"
              "$all"
              "$line_break"
              "$character"
            ];
          };
        };
      };
    };
}
