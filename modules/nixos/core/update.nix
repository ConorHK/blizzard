{
  flake.modules.nixos.update =
    { lib, config, ... }:
    let
      # Stagger auto-upgrades an hour apart so a bad commit can't reboot every
      # host into a broken generation at the same moment — one stays up to alert.
      # Order: puca (unmonitored, canary) → leprechaun (gatus-watched, kept at
      # 06:00 inside gatus's maintenance window) → bananach (runs gatus, last).
      windows = {
        puca = {
          lower = "05:00";
          upper = "06:00";
        };
        leprechaun = {
          lower = "06:00";
          upper = "07:00";
        };
        bananach = {
          lower = "07:00";
          upper = "08:00";
        };
      };
      window =
        windows.${config.networking.hostName} or {
          lower = "06:00";
          upper = "07:00";
        };
    in
    {
      system.autoUpgrade = {
        enable = lib.mkDefault true;

        flake = "github:conorhk/blizzard";
        flags = [ "-L" ];

        dates = "*-*-* ${window.lower}:00";

        allowReboot = true;
        rebootWindow = window;
        operation = "boot";
        randomizedDelaySec = "5min";
      };
    };
}
