{ config, ... }:
{
  nixosHosts.puca = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/puca".imports = with config.flake.modules.nixos; [
    bluetooth
    github-nix-access
    grub-boot
    home-assistant
    server-users
  ];
}
