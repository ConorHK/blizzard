{
  flake.modules.nixos.github-runner =
    { config, pkgs, ... }:
    let
      watchStoreScript = pkgs.writeShellScript "cachix-watch-store" ''
        export CACHIX_AUTH_TOKEN="$(cat ${config.age.secrets.github-runner-cachix.path})"
        exec ${pkgs.cachix}/bin/cachix watch-store conorhk
      '';
    in
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

      systemd.services.cachix-watch-store = {
        description = "Push Nix build outputs to conorhk cachix";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "nix-daemon.service"
          "agenix.service"
        ];
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "10s";
          User = "github-runner-blizzard";
          ExecStart = "${watchStoreScript}";
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
        ];
      };
    };
}
