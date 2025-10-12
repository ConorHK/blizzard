{
  flake.modules.nixos.nixbuild =
    { config, ... }:
    {
      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = "eu.nixbuild.net";
            system = "aarch64-linux";
            maxJobs = 100;
            speedFactor = 2;
            supportedFeatures = [
              "benchmark"
              "big-parallel"
            ];
            sshUser = "root";
            sshKey = "/home/goose/.ssh/nixbuild";
          }
        ];
        settings = {
          trusted-users = [ "goose" ];
          builders-use-substitutes = true;
        };
      };
      programs.ssh = {
        extraConfig = ''
          Host eu.nixbuild.net
          PubkeyAcceptedKeyTypes ssh-ed25519
          ServerAliveInterval 60
          IPQoS throughput
          IdentityFile /home/goose/.ssh/nixbuild
        '';

        knownHosts = {
          nixbuild = {
            hostNames = [ "eu.nixbuild.net" ];
            publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
          };
        };
      };
    };
}
