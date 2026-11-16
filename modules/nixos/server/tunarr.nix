_:
let
  url = "tunarr.goosebox.org";
  port = 8000;
in
{
  flake.monitoringChecks.tunarr = {
    name = "tunarr";
    url = "https://${url}/api/version";
  };

  flake.modules.nixos.tunarr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.blizzard.storage) data media;
      dataDir = "${data}/tunarr";

      # Custom shows rebuilt from a whole local library: show name to source name.
      shows."WSG2 YouTube" = "YouTube";
      channels = [
        1
        2
      ];

      refresh = pkgs.writeShellApplication {
        name = "tunarr-refresh";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          api=''${TUNARR_API:-http://127.0.0.1:${toString port}/api}
          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT

          get() {
            curl -fsS "$api/$1"
          }

          send() {
            curl -fsS -X "$1" "$api/$2" -H 'Content-Type: application/json' --data-binary "@$3"
          }

          refill() {
            local show=$1 source=$2 library id offset=0
            library=$(get media-sources | jq -er --arg n "$source" '.[] | select(.name == $n) | .libraries[0].id')
            id=$(get custom-shows | jq -er --arg n "$show" '.[] | select(.name == $n) | .id')
            : >"$work/programs"
            while get "media-libraries/$library/programs?limit=1000&offset=$offset" >"$work/page"; do
              jq -c '.result[] | {type: "content", duration, id}' "$work/page" >>"$work/programs"
              (( $(jq '.result | length' "$work/page") == 1000 )) || break
              offset=$(( offset + 1000 ))
            done
            jq -s --arg n "$show" '{name: $n, enableSync: false, programs: .}' "$work/programs" >"$work/show"
            send PUT "custom-shows/$id" "$work/show" >/dev/null
            echo "$show: $(wc -l <"$work/programs") programs"
          }

          regenerate() {
            local number=$1 id preview
            id=$(get channels | jq -er --argjson n "$number" '.[] | select(.number == $n) | .id')
            get "channels/$id/schedule" >"$work/schedule"
            case $(jq -r .schedule.type "$work/schedule") in
              random) preview=schedule-slots ;;
              time) preview=schedule-time-slots ;;
              *) echo "channel $number: no slot schedule" >&2; return 1 ;;
            esac
            send POST "channels/$id/$preview" "$work/schedule" >"$work/preview"
            jq --slurpfile s "$work/schedule" '{
              type: $s[0].schedule.type,
              schedule: $s[0].schedule,
              programs: (.programs | keys),
              seed,
              discardCount
            }' "$work/preview" >"$work/programming"
            send POST "channels/$id/programming" "$work/programming" >/dev/null
            echo "channel $number: regenerated"
          }

          ${lib.concatStrings (
            lib.mapAttrsToList (show: source: ''
              refill ${
                lib.escapeShellArgs [
                  show
                  source
                ]
              }
            '') shows
          )}
          for number in ${toString channels}; do
            regenerate "$number"
          done
        '';
      };
    in
    {
      environment.systemPackages = [ refresh ];

      # Tunarr fixes each lineup when built, so new videos air only after a rebuild.
      systemd.services.tunarr-refresh = {
        description = "Rebuild Tunarr lineups with new videos";
        unitConfig.OnFailure = "alert-failure@tunarr-refresh.service";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe refresh;
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          NoNewPrivileges = true;
        };
      };

      systemd.timers.tunarr-refresh = {
        description = "Rebuild Tunarr lineups daily";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "07:00";
          Persistent = true;
        };
      };

      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${media}/bumpers 0775 containers containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet.containers.tunarr.containerConfig = {
        # renovate: datasource=docker depName=docker.io/chrisbenincasa/tunarr
        image = "docker.io/chrisbenincasa/tunarr:2026.11.2";
        publishPorts = [ "127.0.0.1:${toString port}:8000" ];
        volumes = [
          "${dataDir}:/config/tunarr"
          # Same paths as Jellyfin, for direct file access.
          "${media}/movies:/data/movies:ro"
          "${media}/tv:/data/tv:ro"
          "${media}/youtube:/data/youtube:ro"
          "${media}/bumpers:/data/bumpers:ro"
        ];
        devices = [ "nvidia.com/gpu=all" ];
        environments = {
          TZ = "Europe/Dublin";
          TUNARR_SERVER_TRUST_PROXY = "true";
        };
        # Jellyfin and Tunarr reach each other by name.
        networks = [ "jellyfin.network" ];
        noNewPrivileges = true;
      };

      blizzard.backup.jobs.service-data = {
        # Stopped for a consistent SQLite copy.
        paths = [ dataDir ];
        pauseContainers = [ "tunarr" ];
        exclude = [ "${dataDir}/logs" ];
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          extraConfig = "proxy_buffering off;";
        };
      };
    };
}
