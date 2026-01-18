{ inputs, ... }:
{
  nixosHosts.puca = {
    unstable = false;
  };

  flake.modules.nixos."nixosConfigurations/puca".imports = with inputs.self.modules.nixos; [
    bluetooth
    grub-boot
    home-assistant
    server-users
  ];
}
