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
      boot.loader.efi.canTouchEfiVariables = true;
    };
}
