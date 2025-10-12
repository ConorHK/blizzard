{
  flake.modules.nixos.efi =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        efibootmgr
        efitools
        efivar
        fwupd
      ];
      boot = {
        initrd.systemd.enable = true;
        loader.efi.canTouchEfiVariables = true;
      };
    };
}
