{
  flake.modules.nixos.update =
    { lib, ... }:
    {
      system.autoUpgrade = {
        enable = lib.mkDefault true;

        flake = "github:conorhk/blizzard";
        flags = [ "-L" ];

        dates = "*-*-* 06:00:00";

        allowReboot = true;
        rebootWindow = {
          lower = "06:00";
          upper = "07:00";
        };
        operation = "boot";
        randomizedDelaySec = "5min";
      };
    };
}
