{
  flake.modules.nixos.pi-boot = {
    boot.loader = {
      systemd-boot.enable = false;
      efi.canTouchEfiVariables = false;
      generic-extlinux-compatible.enable = true;
      grub.enable = false;
    };
  };
}
