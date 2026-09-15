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

          # kitty opens its first window with no base.
          if [ -z "$attach" ] && [ -z "$base" ]; then
            base=$(uname -n)
            base=''${base%%.*}
          fi

          if [ -n "$attach" ]; then
            session="$attach"
          else
            sessions=$(zmx ls --short 2>/dev/null || true)

            # zmx eats OSC 7 before kitty sees it, but tracks the cwd itself.
            if [ -n "$from" ]; then
              info=$(zmx ls 2>/dev/null | awk -F'\t' -v want="$from" '
                { name = $1; sub(/^.*name=/, "", name)
                  if (name != want) next
                  p = $2; sub(/^pid=/, "", p)
                  c = $5; sub(/^cwd=/, "", c); sub(/^[^:]*:\/\/[^/]*\/?/, "/", c)
                  while (match(c, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
                    n = strtonum("0x" substr(c, RSTART + 1, 2))
                    if (n > 127) break
                    c = substr(c, 1, RSTART - 1) sprintf("%c", n) substr(c, RSTART + 3)
                  }
                  print p "\t" (c ~ /^\// ? c : ""); exit }')
              pid=''${info%%$'\t'*}
              cwd=''${info#*$'\t'}
              # Fallback when the session has no tracked cwd yet.
              if [ -z "$cwd" ] && [ -n "$pid" ]; then
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
