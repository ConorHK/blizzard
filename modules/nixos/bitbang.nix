{
  flake.modules.nixos.bitbang =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.bitbang;

      user = "bitbang";
      shareGroup = "bitbang-share";
      uploadDir = "/upload";
      runBase = "/run/bitbang";

      inherit (cfg) package;
      shell = "${pkgs.bashInteractive}/bin/bash";

      coreutils = "${pkgs.coreutils}/bin";
      utilLinux = "${pkgs.util-linux}/bin";

      share = pkgs.writeShellScriptBin "bitbang-share" ''
        set -euo pipefail

        base=${runBase}

        case "''${1:-}" in
          setup)
            src=$2
            upload=$3

            src=$(${coreutils}/realpath -- "$src")
            if [ ! -d "$src" ]; then
              printf 'Not a directory: %s\n' "$src" >&2
              exit 1
            fi

            ${coreutils}/install -d -m 0711 -o root -g root "$base"
            mp=$(${coreutils}/mktemp -d "$base/XXXXXXXX")
            trap '"$0" teardown "$mp" || true' ERR

            # -r blocks writes; -u/-p grant the service account read access
            # without touching the real files.
            if [ "$upload" = 1 ]; then
              ${coreutils}/mkdir "$mp/files" "$mp/upload"
              ${pkgs.bindfs}/bin/bindfs -r -u ${user} -g ${user} -p u+rD,go-rwx "$src" "$mp/files"
              ${utilLinux}/mount --bind ${uploadDir} "$mp/upload"
              ${coreutils}/chmod 0555 "$mp"
            else
              ${pkgs.bindfs}/bin/bindfs -r -u ${user} -g ${user} -p u+rD,go-rwx "$src" "$mp"
            fi

            printf '%s\n' "$mp"
            ;;

          teardown)
            mp=$2
            case "$mp" in
              "$base"/*) ;;
              *)
                printf 'Refusing to unmount %s\n' "$mp" >&2
                exit 1
                ;;
            esac

            for m in "$mp/files" "$mp/upload" "$mp"; do
              if ${utilLinux}/mountpoint -q "$m" 2>/dev/null; then
                ${utilLinux}/umount -R "$m" 2>/dev/null || ${utilLinux}/umount -R -l "$m" || true
              fi
            done

            # rmdir only: never rm -rf a path that may still be mounted.
            ${coreutils}/rmdir "$mp/files" "$mp/upload" 2>/dev/null || true
            ${coreutils}/rmdir "$mp" 2>/dev/null || true
            ;;

          *)
            printf 'usage: bitbang-share setup DIR 0|1 | teardown MOUNTPOINT\n' >&2
            exit 1
            ;;
        esac
      '';

      wrapper = pkgs.writeShellScriptBin "bitbang" ''
        set -euo pipefail

        sudo=/run/wrappers/bin/sudo
        bitbang=${package}/bin/bitbang

        has_flag() {
          local want=$1 arg
          shift
          for arg in "$@"; do
            if [ "$arg" = "-$want" ] || [ "$arg" = "--$want" ]; then
              return 0
            fi
          done
          return 1
        }

        defaults=()

        add_serve_defaults() {
          local pin raw
          if ! has_flag ephemeral "$@"; then
            defaults+=(-ephemeral)
          fi
          if ! has_flag pin "$@"; then
            raw=$(${coreutils}/od -An -N4 -tu4 </dev/urandom | ${coreutils}/tr -d ' ')
            pin=$(printf '%08d' "$((raw % 100000000))")
            defaults+=(-pin "$pin")
            printf 'PIN for this session: %s\n' "$pin" >&2
          fi
        }

        if [ "''${1:-}" = serve ] && [ "''${2:-}" = files ]; then
          shift 2

          # Split the positional PATH from the flags, honouring flags that
          # take a value.
          path=""
          rest=()
          skip=0
          for arg in "$@"; do
            if [ "$skip" = 1 ]; then
              rest+=("$arg")
              skip=0
              continue
            fi
            case "$arg" in
              -*=*) rest+=("$arg") ;;
              -*)
                rest+=("$arg")
                name=''${arg#-}
                name=''${name#-}
                case " pin program server target video-fd " in
                  *" $name "*) skip=1 ;;
                esac
                ;;
              *)
                if [ -z "$path" ]; then
                  path=$arg
                else
                  rest+=("$arg")
                fi
                ;;
            esac
          done

          path=$(${coreutils}/realpath -- "''${path:-$PWD}")

          upload=0
          if has_flag upload "$@"; then
            upload=1
          fi

          mp=$("$sudo" -- ${share}/bin/bitbang-share setup "$path" "$upload")
          trap '"$sudo" -- ${share}/bin/bitbang-share teardown "$mp" >/dev/null 2>&1 || true' EXIT

          add_serve_defaults serve files "''${rest[@]}"

          status=0
          "$sudo" -H -u ${user} -- "$bitbang" serve files "$mp" "''${rest[@]}" "''${defaults[@]}" || status=$?
          exit "$status"
        fi

        if [ "''${1:-}" = serve ]; then
          add_serve_defaults "$@"

          # -shell-cmd exists only on the shell-serving forms.
          case "''${2:-}" in
            "" | shell | -*)
              if ! has_flag shell-cmd "$@"; then
                defaults+=(-shell-cmd ${shell})
              fi
              ;;
          esac
        fi

        exec "$sudo" -H -u ${user} -- "$bitbang" "$@" "''${defaults[@]}"
      '';
    in
    {
      options.blizzard.bitbang = {
        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.bitbang;
          defaultText = lib.literalExpression "inputs.self.packages.\${system}.bitbang";
          description = "bitbang package the wrapper drives.";
        };

        shareMembers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Accounts that share ${uploadDir} with the ${user} service account.";
        };
      };

      config = {
        users = {
          users = lib.mkMerge [
            {
              ${user} = {
                isSystemUser = true;
                group = user;
                extraGroups = [ shareGroup ];
                home = "/var/lib/${user}";
                createHome = true;
                hashedPassword = "!";
                shell = pkgs.bashInteractive;
              };
            }
            (lib.genAttrs cfg.shareMembers (_: {
              extraGroups = [ shareGroup ];
            }))
          ];

          groups = {
            ${user} = { };
            ${shareGroup} = { };
          };
        };

        systemd.tmpfiles.rules = [
          "d ${uploadDir} 2770 root ${shareGroup} -"
          # Default ACL so uploads stay writable by the sharing accounts.
          "a+ ${uploadDir} - - - - g:${shareGroup}:rwx,d:g:${shareGroup}:rwx"
        ];

        # Rendered after the wheel rule, so NOPASSWD wins for these commands only.
        security.sudo.extraRules = [
          {
            groups = [ "wheel" ];
            runAs = user;
            commands = [
              {
                command = "${package}/bin/bitbang";
                options = [ "NOPASSWD" ];
              }
            ];
          }
          {
            groups = [ "wheel" ];
            runAs = "root";
            commands = [
              {
                command = "${share}/bin/bitbang-share";
                options = [ "NOPASSWD" ];
              }
            ];
          }
        ];

        environment.systemPackages = [ wrapper ];
      };
    };
}
