{
  flake.modules.nixos.core = {
    time.timeZone = "Europe/Dublin";
    i18n.defaultLocale = "en_IE.UTF-8";

    boot.tmp.cleanOnBoot = true;
    zramSwap.enable = true;

    services = {
      fstrim.enable = true;
      irqbalance.enable = true;
    };

    systemd.oomd = {
      enable = true;
      enableSystemSlice = true;
      enableUserSlices = true;
    };
  };
}
