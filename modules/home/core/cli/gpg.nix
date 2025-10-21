{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      # https://github.com/drduh/yubikey-guide
      programs = {
        gpg = {
          enable = true;
        scdaemonSettings = {
          disable-ccid = true;
        };
        };
      };
      services.gpg-agent = {
        enable = true;
        defaultCacheTtl = 1800;
        enableSshSupport = true;
        pinentry.package = pkgs.pinentry-curses;
      };
    };
}
