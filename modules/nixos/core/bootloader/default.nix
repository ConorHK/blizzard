{
  flake.modules.nixos.boot =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        efibootmgr
        efitools
        efivar
        fwupd
      ];
      initrd.systemd.enable = true;
      loader.efi.canTouchEfiVariables = true;
    };
}
