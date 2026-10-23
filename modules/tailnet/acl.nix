{ config, lib, ... }:
let
  addresses = config.flake.tailnetAddresses;
  hosts = config.flake.nixosConfigurations;

  tcp = map (port: "tcp:${toString port}");

  # Each Prometheus host may scrape every other target.
  scrapeGrants = lib.concatLists (
    lib.mapAttrsToList (
      name: nixos:
      let
        inherit (nixos.config.blizzard) metrics metricsExporters;
        targets = lib.attrNames (lib.removeAttrs metrics.targets [ name ]);
      in
      lib.optional (nixos.config.services.prometheus.enable && targets != [ ]) {
        src = [ name ];
        dst = targets;
        ip = tcp [
          metricsExporters.nodePort
          metricsExporters.cadvisorPort
        ];
      }
    ) hosts
  );

  scrapeTests = lib.concatMap (
    grant:
    map (src: {
      inherit src;
      proto = "tcp";
      accept = lib.concatMap (dst: map (ip: "${dst}:${lib.removePrefix "tcp:" ip}") grant.ip) grant.dst;
    }) grant.src
  ) scrapeGrants;

  policy = {
    tagOwners = {
      "tag:workstation" = [ "ConorHK@github" ];
      "tag:client" = [ "ConorHK@github" ];
      "tag:server" = [ "ConorHK@github" ];
      "tag:quarantine" = [ "ConorHK@github" ];
      # Jumphost to workstations.
      "tag:jump" = [ "autogroup:admin" ];
      "tag:game" = [ "conorhk@github" ];
    };

    hosts = addresses;

    ssh = [
      {
        src = [ "tag:workstation" ];
        dst = [
          "tag:workstation"
          "tag:client"
          "tag:server"
          "tag:game"
        ];
        users = [
          "driver"
          "mustang"
        ];
        action = "accept";
      }
      {
        src = [ "tag:jump" ];
        dst = [ "tag:workstation" ];
        users = [ "autogroup:nonroot" ];
        action = "accept";
      }
      {
        src = [ "tag:jump" ];
        dst = [ "tag:server" ];
        users = [ "autogroup:nonroot" ];
        action = "accept";
      }
    ];

    grants = [
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:13378" ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "192.0.1.0/24" ];
        ip = [ "*:*" ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "*" ];
        ip = [ "tcp:22" ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "*" ];
        ip = [ "tcp:80" ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "*" ];
        ip = [ "tcp:443" ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "*" ];
        ip = [ "tcp:8123" ];
      }
      # TODO: expose calibre differently.
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:80" ];
      }
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:443" ];
      }
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:8183" ];
      }
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:8123" ];
      }
      # Navidrome.
      {
        src = [ "tag:client" ];
        dst = [ "tag:server" ];
        ip = [
          "tcp:5274"
          "tcp:4747"
          "tcp:8123"
        ];
      }
      # gatus UI on bananach.
      {
        src = [
          "tag:client"
          "tag:server"
          "tag:workstation"
        ];
        dst = [ "100.96.40.127" ];
        ip = [ "tcp:8080" ];
      }
      {
        src = [
          "tag:client"
          "tag:workstation"
          "autogroup:shared"
        ];
        dst = [ "tag:game" ];
        ip = [
          "tcp:7777"
          "udp:7777"
          "tcp:8888"
          "udp:8888"
        ];
      }
      {
        src = [ "tag:workstation" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:2000-20000" ];
      }
      # gatus on bananach: https, clip, syncthing.
      {
        src = [ "100.96.40.127" ];
        dst = [ "tag:server" ];
        ip = [
          "tcp:443"
          "tcp:7391"
          "tcp:22000"
        ];
      }
      # leprechaun's nginx proxies sluagh's apps.
      {
        src = [ addresses.leprechaun ];
        dst = [ addresses.sluagh ];
        ip = tcp [
          8096
          8080
          8989
          7878
          9696
          6767
          2468
        ];
      }
      {
        src = [
          "tag:client"
          "tag:workstation"
        ];
        dst = [ "100.96.40.127" ];
        ip = [
          "tcp:80"
          "tcp:443"
        ];
      }
      # Home Assistant voice (Wyoming) and music-assistant.
      {
        src = [ "100.95.121.34" ];
        dst = [ "100.91.205.65" ];
        ip = [
          "tcp:10200"
          "tcp:10300"
          "tcp:8095"
          "tcp:8097"
        ];
      }
      # Syncthing to venus from phone.
      {
        src = [ "100.91.205.65" ];
        dst = [ "tag:server" ];
        ip = [ "tcp:43555" ];
      }
      # wg gateway: phone traffic leaves as leprechaun.
      {
        src = [ "100.91.205.65" ];
        dst = [ "100.92.172.125" ];
        ip = [ "tcp:22" ];
      }
      # immich-public-proxy to immich on venus.
      {
        src = [ "100.91.205.65" ];
        dst = [ "100.66.244.36" ];
        ip = [ "tcp:2283" ];
      }
      # gatus on bananach: https, clip, syncthing, home-assistant.
      {
        src = [ "100.96.40.127" ];
        dst = [ "tag:server" ];
        ip = [
          "tcp:443"
          "tcp:7391"
          "tcp:22000"
          "tcp:8123"
        ];
      }
    ]
    ++ scrapeGrants;

    nodeAttrs = [
      # Funnel for workstations and clients.
      {
        target = [
          "tag:workstation"
          "tag:client"
        ];
        attr = [ "funnel" ];
      }
    ];

    # Tailscale refuses a policy that fails these.
    tests = [
      {
        src = "bananach";
        proto = "tcp";
        accept = [
          "puca:8123"
          "leprechaun:443"
        ];
      }
      {
        src = "puca";
        proto = "tcp";
        accept = [ "leprechaun:10300" ];
      }
    ]
    ++ scrapeTests;

    sshTests = [
      {
        src = "tag:workstation";
        dst = [ "tag:server" ];
        accept = [
          "mustang"
          "driver"
        ];
      }
    ];
  };
in
{
  perSystem =
    { pkgs, ... }:
    let
      policyFile = pkgs.writeText "tailnet-policy.json" (builtins.toJSON policy);
    in
    {
      packages.acl-sync = pkgs.writeShellApplication {
        name = "acl-sync";
        runtimeInputs = with pkgs; [
          age
          age-plugin-yubikey
          coreutils
          curl
          diffutils
          git
          gnugrep
          jq
        ];
        text = ''
          root=$(git rev-parse --show-toplevel)
          key=$(age -d -i "$root/.secrets/age-yubikey-identity.pub" \
            "$root/modules/tailnet/secrets/tailscale-api-key.age")
          api=https://api.tailscale.com/api/v2/tailnet/-/acl
          tmp=$(mktemp -d)
          trap 'rm -rf "$tmp"' EXIT

          # Key via stdin config, never argv.
          ts() {
            printf 'user = "%s:"\n' "$key" | curl -sS -K - "$@"
          }

          ts -f -D "$tmp/headers" -H 'Accept: application/json' -o "$tmp/live.json" "$api"
          etag=$(grep -i '^etag:' "$tmp/headers" | cut -d' ' -f2- | tr -d '\r')

          if diff -u --label live --label nix \
               <(jq -S . "$tmp/live.json") <(jq -S . ${policyFile}); then
            echo "Live policy already matches."
            exit 0
          fi

          ts -H 'Content-Type: application/json' \
            --data-binary @${policyFile} "$api/validate" > "$tmp/validate.json"
          jq -r '.data[]?.warnings[]? | "warning: \(.)"' "$tmp/validate.json"
          if jq -e '(.message // "") != "" or any(.data[]?; (.errors // []) != [])' \
               "$tmp/validate.json" > /dev/null; then
            jq . "$tmp/validate.json"
            echo "Tailscale rejected the policy." >&2
            exit 1
          fi
          echo "Policy and tests pass validation."

          # Dry run unless --doit is passed.
          if [ "''${1:-}" != "--doit" ]; then
            exit 0
          fi
          # If-Match refuses to clobber edits made since the diff.
          ts -f -H 'Content-Type: application/json' -H "If-Match: $etag" \
            --data-binary @${policyFile} -o /dev/null "$api"
          echo "Policy applied."
        '';
      };
    };
}
