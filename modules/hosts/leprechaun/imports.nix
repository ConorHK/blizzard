{ config, ... }:
{
  nixosHosts.leprechaun = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    github-nix-access
    github-runner
    podman
    satisfactory
    server-users
    systemd-boot
  ];
}
