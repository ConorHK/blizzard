{
  flake.modules.homeManager.tmux =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # A pane running one of these owns C-hjkl itself, so the key is forwarded
      # instead of moving focus. Stands in for zellij's autolock plugin, which
      # watched the same set of commands.
      ownsNavKeys = "#{m/ri:^[.]?(g?(view|n?vim?x?)(-wrapped)?(diff)?|cnvim|fzf|zoxide|atuin)$,#{pane_current_command}}";

      directions = {
        h = {
          pane = "L";
          arrow = "Left";
        };
        j = {
          pane = "D";
          arrow = "Down";
        };
        k = {
          pane = "U";
          arrow = "Up";
        };
        l = {
          pane = "R";
          arrow = "Right";
        };
      };

      navigation = lib.concatLines (
        lib.mapAttrsToList (key: dir: ''
          bind -n C-${key} if -F "${ownsNavKeys}" "send-keys C-${key}" "select-pane -${dir.pane}"
          bind -n C-${dir.arrow} select-pane -${dir.pane}
          bind C-${key} select-pane -${dir.pane}
          bind -r ${lib.toUpper key} resize-pane -${dir.pane} ${toString config.programs.tmux.resizeAmount}
        '') directions
      );

      # Entry point from the shell, not from inside tmux: switching between live
      # sessions is what tmux's own `choose-tree` on the prefix `s` is for.
      sesh = pkgs.writeShellApplication {
        name = "sesh";
        runtimeInputs = [
          config.programs.tmux.package
          pkgs.fzf
        ];
        text = ''
          if [ -n "''${TMUX:-}" ]; then
            exit 0
          fi

          mapfile -t sessions < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

          if [ "''${#sessions[@]}" -gt 1 ]; then
            target=$(printf '%s\n' "''${sessions[@]}" | fzf --prompt='session> ') || exit 0
            exec tmux attach-session -t "$target"
          elif [ "''${#sessions[@]}" -eq 1 ]; then
            exec tmux attach-session -t "''${sessions[0]}"
          fi

          exec tmux new-session -s default
        '';
      };

      scrollback = pkgs.writeShellApplication {
        name = "tmux-scrollback";
        runtimeInputs = [
          config.programs.tmux.package
          pkgs.coreutils
        ];
        text = ''
          if [ -z "''${TMUX_PANE:-}" ]; then
            echo "tmux-scrollback must run inside tmux" >&2
            exit 1
          fi

          file=$(mktemp -t tmux-scrollback.XXXXXX)
          tmux capture-pane -p -S - -t "$TMUX_PANE" > "$file"
          tmux new-window -n scrollback "''${EDITOR:-vi} '$file'; rm -f '$file'"
        '';
      };
    in
    {
      home.packages = [
        pkgs.fzf
        sesh
      ];

      programs.tmux = {
        enable = true;

        prefix = "C-t";
        keyMode = "vi";
        clock24 = true;
        mouse = true;
        baseIndex = 1;
        escapeTime = 0;
        focusEvents = true;
        historyLimit = 50000;
        terminal = "tmux-256color";
        disableConfirmationPrompt = true;

        extraConfig = ''
          # zellij's compact layout kept the bar and the tab list on top.
          set -g status-position top
          set -g status-justify left
          set -g status-left "#[bold] #S #[nobold]"
          set -g status-left-length 30
          set -g status-right "#{?client_prefix,#[reverse] PREFIX #[noreverse] ,}%H:%M "
          set -g window-status-separator ""
          set -g window-status-format " #I #W "
          set -g window-status-current-format "#[reverse] #I #W#{?window_zoomed_flag, Z,} #[noreverse]"

          set -g renumber-windows on
          # `on` rather than `external` so tmux both emits and accepts OSC 52,
          # which is how oscclip reaches the clipboard over SSH.
          set -g set-clipboard on
          set -g allow-passthrough on
          set -as terminal-features ",*:RGB:usstyle"

          # New windows and splits open where the focused pane is.
          bind c new-window -c "#{pane_current_path}"
          bind v split-window -h -c "#{pane_current_path}"
          bind h split-window -v -c "#{pane_current_path}"

          bind o copy-mode
          bind / copy-mode \; command-prompt -T search -p "search up:" { send-keys -X search-backward "%%" }
          bind r command-prompt -I "#{window_name}" "rename-window -- '%%'"
          bind e run-shell ${lib.getExe scrollback}
          bind Q confirm-before -p "kill this session? (y/n)" kill-session

          bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

          ${navigation}
        '';
      };
    };
}
