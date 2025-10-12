{
  flake.modules.homeManager.core =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables.SHELLS = lib.getExe pkgs.fish;
        shell.enableFishIntegration = true;
      };
      programs = {
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
          settings = {
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
              symbol = " ";
              format = "[$symbol$name \\($state\\)]($style) ";
            };
            nodejs = {
              format = "[$symbol($version )]($style) ";
              disabled = true;
            };
            python = {
              symbol = " ";
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
        };
      };
    };
}
