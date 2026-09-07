{
  perSystem =
    { pkgs, ... }:
    {
      packages.zmx-open = pkgs.writeShellApplication {
        name = "zmx-open";

        runtimeInputs = with pkgs; [
          coreutils
          gawk
          gnugrep
          zmx
        ];

        text = ''
          attach=""
          base=""
          from=""
          cwd=""
          new_family=""

          while [ $# -gt 0 ]; do
            case "$1" in
              --attach) attach="$2"; shift 2 ;;
              --base) base="$2"; shift 2 ;;
              --from) from="$2"; shift 2 ;;
              --cwd) cwd="$2"; shift 2 ;;
              --new-family) new_family=1; shift ;;
              *) printf 'zmx-open: unknown option %s\n' "$1" >&2; exit 2 ;;
            esac
          done

          if [ -z "$attach" ] && [ -z "$base" ]; then
            printf 'zmx-open: --attach or --base is required\n' >&2
            exit 2
          fi

          if [ -n "$attach" ]; then
            session="$attach"
          else
            sessions=$(zmx ls --short 2>/dev/null || true)

            # zmx swallows escapes, so cwd comes from the session leader.
            if [ -n "$from" ]; then
              pid=$(zmx ls 2>/dev/null | awk -F'\t' -v want="$from" '
                { name = $1; sub(/^[[:space:]]*name=/, "", name)
                  if (name == want) { p = $2; sub(/^pid=/, "", p); print p; exit } }')
              if [ -n "$pid" ]; then
                cwd=$(readlink "/proc/$pid/cwd" || true)
              fi
            fi

            has_family() {
              printf '%s\n' "$sessions" | awk -v b="$1" '
                index($0, b ".") == 1 && substr($0, length(b) + 2) ~ /^[0-9]+$/ { found = 1; exit }
                END { exit !found }'
            }

            if [ -n "$new_family" ] && has_family "$base"; then
              suffix=2
              while has_family "$base-$suffix"; do
                suffix=$((suffix + 1))
              done
              base="$base-$suffix"
            fi

            n=1
            while printf '%s\n' "$sessions" | grep -qxF "$base.$n"; do
              n=$((n + 1))
            done
            session="$base.$n"
          fi

          if [ ! -d "$cwd" ]; then
            cwd=''${HOME:-/}
          fi

          set_var() {
            printf '\033]1337;SetUserVar=%s=%s\007' "$1" "$(printf %s "$2" | base64 -w0)"
          }

          # Reported before the exec; zmx would eat these.
          printf '\033]2;%s\007' "$session"
          set_var zmx_session "$session"
          set_var remote_host "$(uname -n)"

          cd "$cwd"
          exec zmx attach "$session"
        '';

        meta = {
          description = "Open or reattach a zmx session for a kitty pane";
          mainProgram = "zmx-open";
        };
      };
    };
}
