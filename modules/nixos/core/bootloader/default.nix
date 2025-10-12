{
  flake.modules.nixos.boot =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        efibootmgr
        efitools
        efivar
        fwupd
      ];
      initrd.systemd.enable = true;
      loader.efi.canTouchEfiVariables = lib.mkDefault true;
    };
}
