{ config, ... }:
{
  nixosHosts.leprechaun = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    backrest
    github-nix-access
    github-runner
    mealie
    podman
    quadlet
    satisfactory
    server-users
    systemd-boot
  ];
}
