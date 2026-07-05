{
  flake.modules.nixos.update =
    { lib, ... }:
    {
      system.autoUpgrade = {
        enable = lib.mkDefault true;

        # `stable` is fast-forwarded to main by CI only after every host builds
        # (see .github/workflows/build.yml), so a broken push to main is never
        # auto-deployed.
        flake = "github:conorhk/blizzard/stable";
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
