{ inputs, ... }:
{
  nixosHosts.puca = {
    unstable = false;
  };

  flake.modules.nixos."nixosConfigurations/puca".imports = with inputs.self.modules.nixos; [
    home-assistant
    server-users
    grub-boot
  ];
}
