# SCAFFOLD — dormant, not yet wired to a real service, not build-verified.
# The container wiring depends on Cloudflare-side setup that does not exist yet
# (tunnel UUID + credentials). It evaluates as-is because `shares` is empty.
# See ./README.md for the full plan, decisions, and manual setup steps.
_:
let
  # ── Shares ──────────────────────────────────────────────────────────────────
  # Empty until a real service is wired. To add one, uncomment the example and
  # fill in the fields. Adding a share here is the ONLY Nix change needed.
  #
  #   network  = the target service's existing podman network (isolation boundary)
  #   target   = container DNS name + port on that network (NOT a host loopback port)
  #   hostname = public name on the Cloudflare zone
  #   tunnel   = per-share tunnel UUID from `cloudflared tunnel create`
  #              (one tunnel per share keeps each connector on one network — see README)
  #
  # Each share `<name>` also expects an agenix secret `cloudflare-share-<name>`
  # backed by ./secrets/<name>.json.age (the tunnel credentials file).
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

      # cloudflared reads a local config.yml → locally-managed ingress. Targets are
      # pinned here and cannot be re-pointed from the Cloudflare side. Ingress lists
      # only this share's hostname; everything else 404s at the connector.
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

      # One dormant cloudflared container per share, joined to ONLY that share's
      # podman network. autoStart = false → exists after rebuild, runs only when
      # `share-open` starts it. Unit name: cloudflared-share-<name>.service (user).
      mkContainer = name: share: {
        name = "cloudflared-share-${name}";
        value = {
          autoStart = false;
          containerConfig = {
            # renovate: datasource=docker depName=docker.io/cloudflare/cloudflared
            image = "docker.io/cloudflare/cloudflared:2024.12.2";
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

      # Drive the rootless `containers` user's systemd, same as the `asc` alias.
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
        # Transient timer stops the connector after the window, then self-destructs.
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
        # Cancel the pending auto-close timer if the window hasn't elapsed.
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
      # Per-share tunnel credentials, readable by the rootless container user.
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

      # NOTE: no firewall ports and no `wantedBy` boot target — exposure is
      # outbound-only and dormant. A reboot mid-window leaves shares CLOSED.
    };
}
