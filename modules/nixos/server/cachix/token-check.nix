_: {
  flake.modules.nixos.cachix-token-check =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.cachixTokenCheck;

      check = pkgs.writeShellApplication {
        name = "cachix-token-check";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          token_file=$1
          cache=$2
          expires=$3
          warn_days=$4
          api=''${CACHIX_API:-https://app.cachix.org/api/v1}

          token=$(<"$token_file")
          problems=()
          priority=3

          # JWT payloads are unpadded base64url.
          payload=$(cut -d. -f2 <<<"$token" | tr '_-' '/+')
          while (( ''${#payload} % 4 )); do payload+="="; done
          exp=$(base64 -d <<<"$payload" 2>/dev/null | jq -r '.exp // empty' 2>/dev/null || true)

          if [ -z "$exp" ] && [ "$expires" != never ] && [ -n "$expires" ]; then
            exp=$(date -u -d "$expires" +%s)
          fi

          if [ -n "$exp" ]; then
            day=$(date -u -d "@$exp" +%F)
            left=$(( (exp - $(date +%s)) / 86400 ))
            unit=days
            if (( left == 1 )); then unit=day; fi
            if (( exp <= $(date +%s) )); then
              problems+=("Expired on $day.")
              priority=4
            elif (( left < warn_days )); then
              problems+=("Expires in $left $unit, on $day.")
              if (( left <= 3 )); then priority=4; fi
            else
              echo "token expires on $day, in $left $unit"
            fi
          elif [ "$expires" != never ]; then
            problems+=("Expiry unknown. Set blizzard.cachixTokenCheck.expires.")
          fi

          # A bad token reads as anonymous.
          permission=$(printf 'Authorization: Bearer %s\n' "$token" \
            | curl -fsS --retry 3 --retry-all-errors --max-time 20 -H @- "$api/cache/$cache" \
            | jq -r .permission)
          case $permission in
            Write | Admin) echo "token can push to $cache" ;;
            *)
              problems+=("Cannot push to $cache: permission $permission.")
              priority=4
              ;;
          esac

          if (( ''${#problems[@]} )); then
            alert-send "Cachix token" "''${problems[*]}" "$priority" warning
          fi
        '';
      };
    in
    {
      options.blizzard.cachixTokenCheck = {
        tokenFile = lib.mkOption {
          type = lib.types.path;
          description = "Cachix auth token to watch.";
        };

        cache = lib.mkOption {
          type = lib.types.str;
          description = "Cache the token must push to.";
        };

        expires = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}|never");
          default = null;
          description = "Expiry date from the cachix UI, or never. Used when the token carries no exp claim.";
        };

        warnDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 14;
          description = "Days before expiry that alerts start.";
        };
      };

      config = {
        environment.systemPackages = [ check ];

        systemd.services.cachix-token-check = {
          description = "Warn before the cachix token stops working";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # The watchdog must not fail silently.
          unitConfig.OnFailure = "alert-failure@cachix-token-check.service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe check)
              cfg.tokenFile
              cfg.cache
              (if cfg.expires == null then "" else cfg.expires)
              (toString cfg.warnDays)
            ];
            ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };

        systemd.timers.cachix-token-check = {
          description = "Check the cachix token daily";
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
