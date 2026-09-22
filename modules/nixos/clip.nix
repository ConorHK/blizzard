let
  port = 7391;
  host = "leprechaun";
in
{
  flake = {
    monitoringChecks.clip = {
      name = "clip";
      url = "tcp://${host}:${toString port}";
      conditions = [ "[CONNECTED] == true" ];
    };

    modules.nixos.clip-server =
      { pkgs, ... }:
      let
        server = pkgs.writers.writePython3Bin "clip-server" { flakeIgnore = [ "E501" ]; } (
          builtins.readFile ./clip-server.py
        );
      in
      {
        # Never opened in the firewall: wg0 and tailscale0 are trusted, everything else drops.
        systemd.services.clip = {
          description = "Shared string mailbox";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${server}/bin/clip-server ${toString port}";
            DynamicUser = true;
            StateDirectory = "clip";
            Restart = "always";
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            SystemCallFilter = [ "@system-service" ];
          };
        };

      };

    modules.nixos.clip =
      { pkgs, ... }:
      {
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "clip";
            runtimeInputs = [
              pkgs.curl
              pkgs.coreutils
            ];
            text = ''
              slot="''${1:-default}"
              url="''${CLIP_URL:-http://${host}:${toString port}}/$slot"

              # Only a pipe or a file on stdin means write; anything else reads,
              # so a stray `< /dev/null` cannot wipe the slot.
              if [ -p /dev/stdin ] || [ -f /dev/stdin ]; then
                curl -fsS -T - "$url"
                exit
              fi

              # Body to a file, so an empty slot reads as a sentence, not curl's 404.
              body=$(mktemp)
              trap 'rm -f "$body"' EXIT
              code=$(curl -sS -o "$body" -w '%{http_code}' "$url")

              case "$code" in
                200) cat "$body" ;;
                404) echo "clip: slot '$slot' is empty" >&2; exit 1 ;;
                *) echo "clip: server returned $code" >&2; exit 1 ;;
              esac
            '';
          })
        ];
      };
  };
}
