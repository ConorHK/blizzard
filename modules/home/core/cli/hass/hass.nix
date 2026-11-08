_: {
  flake.modules.homeManager.hass =
    { config, ... }:
    {
      age.secrets.hass-token.rekeyFile = ./hass-token.age;

      # The pi jail hides home; bind read-only.
      programs.pi.jail.readOnly = [ config.age.secrets.hass-token.path ];

      xdg.configFile."hass/token".source =
        config.lib.file.mkOutOfStoreSymlink config.age.secrets.hass-token.path;
    };
}
