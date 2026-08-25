{
  nixpkgs.allowedInsecurePackages = [
    "nodejs-20.20.2"
    "nodejs-slim-20.20.2"
  ];

  flake.modules.nixos.github-runner =
    { config, pkgs, ... }:
    {
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
      };
    };
}
