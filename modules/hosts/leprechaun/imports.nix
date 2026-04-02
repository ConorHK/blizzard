{ config, ... }:
{
  nixosHosts.leprechaun = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    systemd-boot
    server-users
    podman
    satisfactory
    github-runner
  ];
}
