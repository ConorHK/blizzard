{ config, ... }:
let
  inherit (config.flake.modules.nixos) deployed-lag;
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
      imports = [ deployed-lag ];

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

      # Expired tokens stall every CI push.
      blizzard.secretExpiry.secrets = {
        cachix = {
          file = config.age.secrets.github-runner-cachix.path;
          probe = config.blizzard.secretExpiry.probes.cachix "conorhk";
        };
        github-runner = {
          file = config.age.secrets.github-runner-token.path;
          probe = config.blizzard.secretExpiry.probes.github;
        };
      };

      blizzard.deployedLag.remote = "https://github.com/ConorHK/blizzard";

      services.github-runners.blizzard = {
        enable = true;
        url = "https://github.com/ConorHK/blizzard";
        tokenFile = config.age.secrets.github-runner-token.path;
        extraLabels = [
          "nix"
          "self-hosted"
          "x86_64-linux"
        ];
        extraPackages = with pkgs; [
          cachix
          git
          gh
          jq
          renovate
        ];
        serviceOverrides = {
          Restart = lib.mkForce "always";
          RestartSec = "30s";
          MemoryHigh = "5G";
          MemoryMax = "7G";
        };
      };

      systemd.services.github-runner-blizzard.unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
    };
}
