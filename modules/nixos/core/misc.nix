{
  flake.modules.nixos.core = {
    # timezone / locale
    time.timeZone = "Europe/Dublin";
    i18n.defaultLocale = "en_IE.UTF-8";

    boot.tmp.cleanOnBoot = true;
  };
}
