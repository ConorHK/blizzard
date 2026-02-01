{ inputs, ... }:
{
  nixosHosts.puca = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/puca".imports = with inputs.self.modules.nixos; [
    bluetooth
    grub-boot
    home-assistant
    server-users
    tsidp
  ];
}
