{
  flake.modules.homeManager.gammastep = {
    services.gammastep = {
      enable = true;
      provider = "manual";
      latitude = 53.26;
      longitude = 6.15;
      temperature.day = 5500;
      temperature.night = 1900;
      tray = false;
    };
  };
}
