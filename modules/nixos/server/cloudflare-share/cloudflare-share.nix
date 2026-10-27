# Dormant scaffold, not build-verified. See ./README.md.
_:
let
  # Fields are described in ./README.md.
  shares = {
    # budget = {
    #   network  = "actual-budget.network";
    #   target   = "http://actual-budget:5006";
    #   hostname = "budget.share.goosebox.org";
    #   tunnel   = "REPLACE_WITH_TUNNEL_UUID";
    # };
  };
in
{
  flake.modules.nixos.cloudflare-share =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      knownShares = lib.attrNames shares;

      # Local ingress; Cloudflare cannot re-point it.
      mkConfig =
        name: share:
        pkgs.writeText "cloudflared-${name}.yml" ''
          tunnel: ${share.tunnel}
          credentials-file: /etc/cloudflared/creds.json
          ingress:
            - hostname: ${share.hostname}
              service: ${share.target}
            - service: http_status:404
        '';

      # Joins only its share's network.
      mkContainer = name: share: {
        name = "cloudflared-share-${name}";
        value = {
          autoStart = false;
          containerConfig = {
            # renovate: datasource=docker depName=docker.io/cloudflare/cloudflared
            image = "docker.io/cloudflare/cloudflared:2026.10.4";
            exec = "tunnel --no-autoupdate --config /etc/cloudflared/config.yml run";
            volumes = [
              "${mkConfig name share}:/etc/cloudflared/config.yml:ro"
              "${config.age.secrets."cloudflare-share-${name}".path}:/etc/cloudflared/creds.json:ro"
            ];
            networks = [ share.network ];
            noNewPrivileges = true;
          };
        };
      };

      # Act as the rootless containers user.
      asc = "${pkgs.sudo}/bin/sudo -u containers XDG_RUNTIME_DIR=/run/user/$(id -u containers)";
      knownList = lib.concatStringsSep " " knownShares;

      shareOpen = pkgs.writeShellScriptBin "share-open" ''
        set -euo pipefail
        svc="''${1:-}"
        dur="''${2:-}"
        known="${knownList}"
        if [ -z "$svc" ] || [ -z "$dur" ]; then
          echo "usage: share-open <service> <duration>   (duration is REQUIRED, e.g. 4h)" >&2
          echo "known shares: ''${known:-<none configured>}" >&2
          exit 1
        fi
        case " $known " in *" $svc "*) ;; *)
          echo "unknown share: $svc (known: ''${known:-<none>})" >&2; exit 1;; esac
        unit="cloudflared-share-$svc.service"
        ${asc} systemctl --user start "$unit"
        # Stop the connector when the window ends.
        ${asc} systemd-run --user --on-active="$dur" \
          --unit="share-close-$svc" \
          systemctl --user stop "$unit"
        echo "opened $svc for $dur (auto-closes via timer share-close-$svc)"
      '';

      shareClose = pkgs.writeShellScriptBin "share-close" ''
        set -euo pipefail
        svc="''${1:-}"
        [ -n "$svc" ] || { echo "usage: share-close <service>" >&2; exit 1; }
        ${asc} systemctl --user stop "cloudflared-share-$svc.service" || true
        # Cancel the pending auto-close timer.
        ${asc} systemctl --user stop "share-close-$svc.timer" 2>/dev/null || true
        echo "closed $svc"
      '';

      shareStatus = pkgs.writeShellScriptBin "share-status" ''
        set -euo pipefail
        known="${knownList}"
        if [ -z "$known" ]; then echo "no shares configured"; exit 0; fi
        for svc in $known; do
          state="$(${asc} systemctl --user is-active "cloudflared-share-$svc.service" 2>/dev/null || true)"
          left="$(${asc} systemctl --user list-timers "share-close-$svc.timer" --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $5, $6}')"
          printf '%-20s %s%s\n' "$svc" "$state" "''${left:+  (closes in $left)}"
        done
      '';
    in
    {
      # Tunnel credentials for the rootless user.
      age.secrets = lib.mapAttrs' (name: _: {
        name = "cloudflare-share-${name}";
        value = {
          rekeyFile = ./secrets/${name}.json.age;
          owner = "containers";
          mode = "0400";
        };
      }) shares;

      home-manager.users.containers.virtualisation.quadlet.containers = lib.listToAttrs (
        lib.mapAttrsToList mkContainer shares
      );

      environment.systemPackages = [
        shareOpen
        shareClose
        shareStatus
      ];

      # No boot target, so reboots close shares.
    };
}
