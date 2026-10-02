{
  flake.modules.nixos.core =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = lib.attrValues {
        inherit (pkgs)
          dig
          file
          git
          killall
          lsof
          pciutils
          ripgrep
          tree
          unzip
          usbutils
          wget
          zip
          ;
      };

      programs.htop.enable = true;
    };
}
