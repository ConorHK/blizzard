{ config, ... }:
let
  inherit (config.flake.modules.nixos) container-smoke deployed-lag;
in
{
  flake.modules.nixos.github-runner =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        container-smoke
        deployed-lag
      ];

      users.users.github-runner-blizzard = {
        isSystemUser = true;
        group = "github-runner-blizzard";
      };
      users.groups.github-runner-blizzard = { };

      age.secrets = {
        github-runner-token = {
          rekeyFile = ./secrets/github-runner-token.age;
          owner = "github-runner-blizzard";
        };
        github-runner-cachix = {
          rekeyFile = ../cachix/secrets/cachix.age;
          owner = "github-runner-blizzard";
        };
        # Actions write on blizzard only.
        github-dispatch-token.rekeyFile = ./secrets/github-dispatch-token.age;
      };

      # Expired tokens stall every CI push.
      blizzard = {
        secretExpiry.secrets = {
          # Issuers report no expiry for these.
          cachix = {
            file = config.age.secrets.github-runner-cachix.path;
            expires = "never";
            probe = config.blizzard.secretExpiry.probes.cachix "conorhk";
          };
          github-dispatch = {
            file = config.age.secrets.github-dispatch-token.path;
            expires = "never";
            probe = config.blizzard.secretExpiry.probes.github;
          };
        };

        deployedLag.remote = "https://github.com/ConorHK/blizzard";
        containerSmoke.requester = "github-runner-blizzard";
      };

      # Setting changes re-register; the token expires hourly.
      services.github-runners.blizzard = {
        enable = true;
        url = "https://github.com/ConorHK/blizzard";
        tokenFile = config.age.secrets.github-runner-token.path;
        extraLabels = [
          "nix"
          "self-hosted"
          "x86_64-linux"
        ];
        extraPackages =
          with pkgs;
          [
            cachix
            git
            gh
            jq
            # Renovate updates npm lockfiles.
            nodejs
            renovate
            systemd
          ]
          ++ [ config.blizzard.containerSmoke.gateCheck ];
        serviceOverrides = {
          Restart = lib.mkForce "always";
          RestartSec = "30s";
          # flake check eval peaks near 8.3G.
          MemoryHigh = "10G";
          MemoryMax = "12G";
        };
      };

      systemd = {
        # CI swapping into zram froze the host.
        slices.ci.sliceConfig = {
          MemoryHigh = "9G";
          MemoryMax = "10G";
          MemorySwapMax = 0;
          CPUWeight = 20;
          IOWeight = 20;
        };

        services = {
          github-runner-blizzard = {
            unitConfig = {
              StartLimitIntervalSec = 300;
              StartLimitBurst = 5;
            };
            serviceConfig = {
              Slice = "ci.slice";
              ReadWritePaths = [ "-/var/lib/container-smoke/requests" ];
            };
          };
          # Builds run in the daemon's cgroup.
          nix-daemon.serviceConfig.Slice = "ci.slice";

          # GitHub cron runs hours late.
          container-smoke-dispatch = {
            description = "Dispatch the container-smoke workflow";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            unitConfig.OnFailure = "alert-failure@container-smoke-dispatch.service";
            path = [ pkgs.curl ];
            script = ''
              printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' <"$CREDENTIALS_DIRECTORY/token")" |
                curl -fsS --retry 3 --retry-all-errors --max-time 20 -H @- \
                  -H 'Accept: application/vnd.github+json' -d '{"ref":"main"}' \
                  https://api.github.com/repos/ConorHK/blizzard/actions/workflows/container-smoke.yml/dispatches
            '';
            serviceConfig = {
              Type = "oneshot";
              DynamicUser = true;
              LoadCredential = "token:${config.age.secrets.github-dispatch-token.path}";
            };
          };
        };

        timers.container-smoke-dispatch = {
          wantedBy = [ "timers.target" ];
          # Retries runs deferred or cut by reboots.
          timerConfig.OnCalendar = "hourly";
        };
      };
    };
}
