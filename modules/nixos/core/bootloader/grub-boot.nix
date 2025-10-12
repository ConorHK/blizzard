{
  flake.modules.nixos.grub-boot =
    { lib, ... }:
    {
      boot.loader.grub = {
        enable = true;
        devices = lib.mkDefault [ "/dev/sda" ];
        efiSupport = false;
        useOSProber = false;
      };
    };
}
