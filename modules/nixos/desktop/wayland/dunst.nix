{ config, ... }:
let
  inherit (config.flake.wrappers.dunst) install;
in
{
  flake.modules.nixos.desktop =
    { config, lib, ... }:
    let
      dunst = config.wrappers.dunst.wrapper;
      people = lib.attrNames (lib.filterAttrs (_: user: user.isNormalUser) config.users.users);
    in
    {
      imports = [ install ];
      wrappers.dunst = {
        enable = true;
        iconDirs = [ "/run/current-system/sw" ] ++ map (name: "/etc/profiles/per-user/${name}") people;
      };

      # D-Bus starts this unit for the first notification.
      services.dbus.packages = [ dunst ];

      systemd.user.services.dunst = {
        description = "Dunst notification daemon";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        enableDefaultPath = false;
        serviceConfig = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          ExecStart = lib.getExe dunst;
          ExecReload = "${dunst}/bin/dunstctl reload";
        };
      };
    };
}
