{
  flake.modules.nixos.grub-boot =
    { lib, ... }:
    {
      boot.loader.grub = {
        enable = true;
        version = 2;
        devices = lib.mkDefault [ "/dev/sda" ];
        efiSupport = false;
        useOSProber = false;
      };
    };
}
