_: {
  flake.modules.nixos.secret-expiry =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.secretExpiry;

      # Probe: stdout expiry time; exit 3 rejects.
      probes = {
        cachix =
          cache:
          pkgs.writeShellApplication {
            name = "probe-cachix-${cache}";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.jq
            ];
            text = ''
              api=''${CACHIX_API:-https://app.cachix.org/api/v1}
              [ -r "$1" ] || exit 2
              token=$(<"$1")

              # JWT payloads are unpadded base64url.
              payload=$(cut -d. -f2 <<<"$token" | tr '_-' '/+')
              while (( ''${#payload} % 4 )); do payload+="="; done
              exp=$(base64 -d <<<"$payload" 2>/dev/null | jq -r '.exp // empty' 2>/dev/null || true)

              # A bad token reads as anonymous.
              response=$(printf 'Authorization: Bearer %s\n' "$token" \
                | curl -fsS --retry 3 --retry-all-errors --max-time 20 -H @- "$api/cache/${cache}") || exit 2
              permission=$(jq -r .permission <<<"$response")
              case $permission in
                Write | Admin) ;;
                *)
                  echo "Cannot push to ${cache}: permission $permission."
                  exit 3
                  ;;
              esac
              if [ -n "$exp" ]; then date -u -d "@$exp" '+%F %T UTC'; fi
            '';
          };

        github = pkgs.writeShellApplication {
          name = "probe-github";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
            pkgs.gnused
          ];
          text = ''
            api=''${GITHUB_API:-https://api.github.com}
            [ -r "$1" ] || exit 2
            # Raw token, or nix.conf access-tokens.
            token=$(sed -n 's/.*github\.com=\([^ ]*\).*/\1/p' "$1" | head -n 1)
            if [ -z "$token" ]; then token=$(tr -d '[:space:]' <"$1"); fi

            headers=$(mktemp)
            status=$(printf 'Authorization: Bearer %s\n' "$token" \
              | curl -sS --retry 3 --retry-all-errors --max-time 20 -o /dev/null -D "$headers" -w '%{http_code}' \
                  -H @- "$api/rate_limit") || exit 2
            case $status in
              200)
                sed -n 's/^github-authentication-token-expiration: *\(.*[^[:space:]]\)[[:space:]]*$/\1/Ip' "$headers" \
                  | head -n 1
                ;;
              401)
                echo "GitHub rejects the token."
                exit 3
                ;;
              *)
                echo "GitHub answered HTTP $status" >&2
                exit 2
                ;;
            esac
          '';
        };
      };

      manifest = pkgs.writeText "secret-expiry.json" (
        builtins.toJSON (
          lib.mapAttrsToList (name: secret: {
            inherit name;
            file = toString secret.file;
            expires = if secret.expires == null then "" else secret.expires;
            probe = if secret.probe == null then "" else lib.getExe secret.probe;
          }) cfg.secrets
        )
      );

      check = pkgs.writeShellApplication {
        name = "secret-expiry-check";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          manifest=$1
          warn_days=$2
          now=$(date +%s)
          broken=0

          # Unit separator keeps empty fields.
          while IFS=$'\x1f' read -r name file expires probe; do
            problems=()
            priority=3
            exp=""

            if [ -n "$probe" ]; then
              rc=0
              out=$("$probe" "$file" </dev/null) || rc=$?
              case $rc in
                0)
                  if [ -n "$out" ] && ! exp=$(date -u -d "$out" +%s); then
                    echo "$name: probe printed a bad date: $out"
                    broken=1
                    continue
                  fi
                  ;;
                3)
                  alert-send "$name secret" "$out" 4 warning
                  continue
                  ;;
                *)
                  echo "$name: probe failed with exit $rc"
                  broken=1
                  continue
                  ;;
              esac
            fi

            if [ -z "$exp" ] && [ -n "$expires" ] && [ "$expires" != never ] \
              && ! exp=$(date -u -d "$expires" +%s); then
              echo "$name: bad expires date: $expires"
              broken=1
              continue
            fi

            if [ -n "$exp" ]; then
              day=$(date -u -d "@$exp" +%F)
              left=$(( (exp - now) / 86400 ))
              unit=days
              if (( left == 1 )); then unit=day; fi
              if (( exp <= now )); then
                problems+=("Expired on $day.")
                priority=4
              elif (( left < warn_days )); then
                problems+=("Expires in $left $unit, on $day.")
                if (( left <= 3 )); then priority=4; fi
              else
                echo "$name: expires on $day, in $left $unit"
              fi
            elif [ "$expires" != never ]; then
              problems+=("Expiry unknown. Set blizzard.secretExpiry.secrets.$name.expires.")
            fi

            if (( ''${#problems[@]} )); then
              alert-send "$name secret" "''${problems[*]}" "$priority" warning
            fi
          done < <(jq -r '.[] | [.name, .file, .expires, .probe] | join("\u001f")' "$manifest")

          exit "$broken"
        '';
      };
    in
    {
      options.blizzard.secretExpiry = {
        warnDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 14;
          description = "Days before expiry that alerts start.";
        };

        probes = lib.mkOption {
          type = lib.types.raw;
          readOnly = true;
          default = probes;
          description = "Live checks: `cachix <cache>` and `github`.";
        };

        secrets = lib.mkOption {
          default = { };
          description = "Credentials that expire or can be revoked.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                file = lib.mkOption {
                  type = lib.types.path;
                  description = "Decrypted secret the probe reads.";
                };

                expires = lib.mkOption {
                  type = lib.types.nullOr (lib.types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}|never");
                  default = null;
                  description = "Expiry from the issuer, or never. Used when the probe reports none.";
                };

                probe = lib.mkOption {
                  type = lib.types.nullOr lib.types.package;
                  default = null;
                  description = "Live check, usually from `blizzard.secretExpiry.probes`.";
                };
              };
            }
          );
        };
      };

      config = lib.mkIf (cfg.secrets != { }) {
        environment.systemPackages = [ check ];

        systemd.services.secret-expiry = {
          description = "Warn before credentials stop working";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # The watchdog must not fail silently.
          unitConfig.OnFailure = "alert-failure@secret-expiry.service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe check)
              "${manifest}"
              (toString cfg.warnDays)
            ];
            ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };

        systemd.timers.secret-expiry = {
          description = "Check expiring credentials daily";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
        };
      };
    };
}
