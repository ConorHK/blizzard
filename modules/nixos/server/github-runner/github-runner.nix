{ config, ... }:
let
  inherit (config.flake.modules.nixos)
    ci-runner
    container-smoke
    deployed-lag
    github-nix-access
    ;
in
{
  flake.modules.nixos = {
    # A plain CI runner; any host with spare RAM can carry one.
    ci-runner =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.blizzard.ciRunner;
      in
      {
        imports = [ github-nix-access ];

        options.blizzard.ciRunner = {
          memoryHigh = lib.mkOption {
            type = lib.types.str;
            default = "14G";
            description = "Soft memory cap for CI jobs and builds.";
          };
          memoryMax = lib.mkOption {
            type = lib.types.str;
            default = "16G";
            description = "Hard memory cap for CI jobs and builds.";
          };
          extraLabels = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Runner labels beyond the shared ones.";
          };
          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
            description = "Packages added to the runner's PATH.";
          };
          readWritePaths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Extra paths the runner may write.";
          };
        };

        config = {
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
            ]
            ++ cfg.extraLabels;
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
              ++ cfg.extraPackages;
            serviceOverrides = {
              Restart = lib.mkForce "always";
              RestartSec = "30s";
              # flake check eval peaks near 8.3G.
              MemoryHigh = cfg.memoryHigh;
              MemoryMax = cfg.memoryMax;
              # Reads the token that fetches private flake inputs.
              SupplementaryGroups = [ "nix-github" ];
            };
          };

          systemd = {
            # CI swapping into zram froze the host.
            slices.ci.sliceConfig = {
              MemoryHigh = cfg.memoryHigh;
              MemoryMax = cfg.memoryMax;
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
                  ReadWritePaths = cfg.readWritePaths;
                };
              };
              # Builds run in the daemon's cgroup.
              nix-daemon.serviceConfig.Slice = "ci.slice";
            };
          };
        };
      };

    # The runner that also owns container smoke tests and deploy checks.
    github-runner =
      {
        config,
        pkgs,
        ...
      }:
      {
        imports = [
          ci-runner
          container-smoke
          deployed-lag
        ];

        # Actions write on blizzard only.
        age.secrets.github-dispatch-token.rekeyFile = ./secrets/github-dispatch-token.age;

        # Expired tokens stall every CI push.
        blizzard = {
          ciRunner = {
            # container-smoke.yml needs this host's data and gate.
            extraLabels = [ "container-smoke" ];
            extraPackages = [ config.blizzard.containerSmoke.gateCheck ];
            readWritePaths = [ "-/var/lib/container-smoke/requests" ];
          };

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

        systemd = {
          services.container-smoke-dispatch = {
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

          # GitHub cron runs hours late.
          timers.container-smoke-dispatch = {
            wantedBy = [ "timers.target" ];
            # Retries runs deferred or cut by reboots.
            timerConfig.OnCalendar = "hourly";
          };
        };
      };
  };
}
