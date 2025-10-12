{ inputs, ... }:
{
  nixosHosts.abhartach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/abhartach".imports = with inputs.self.modules.nixos; [
    amdgpu

    cnvim
    cachix

    desktop
    gaming

    home-manager

    kvm-amd
    secure-boot
    sunshine
    virtualization
    nixbuild
  ];
}
