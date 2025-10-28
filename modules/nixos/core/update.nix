{
  flake.modules.nixos.update =
    { lib, ... }:
    {
      system.autoUpgrade = {
        enable = lib.mkDefault true;

        flake = "github:conorhk/blizzard";
        flags = [ "-L" ];

        dates = "*-*-* 04:30:00";

        allowReboot = true;
        rebootWindow = {
          lower = "04:25";
          upper = "05:45";
        };
        operation = "boot";
        randomizedDelaySec = "5min";
      };
    };
}
