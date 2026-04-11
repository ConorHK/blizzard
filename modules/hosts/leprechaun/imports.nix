{ config, ... }:
{
  nixosHosts.leprechaun = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    actual-budget
    github-nix-access
    github-runner
    mealie
    nginx
    podman
    quadlet
    restic
    satisfactory
    server-users
    systemd-boot
  ];
}
