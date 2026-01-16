{
  flake.modules.nixos.desktop =
    { pkgs, lib, ... }:
    {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
        xwayland.enable = true;
      };
      programs.uwsm.enable = true;
      security.pam.services.hyprlock = { };
      users = {
        users.greeter.group = "greeter";
        groups.greeter = { };
      };

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --remember --cmd ${pkgs.hyprland}/bin/start-hyprland";
            user = "greeter";
          };
          initial_session = {
            command = "${pkgs.hyprland}/bin/start-hyprland";
            user = "goose";
          };
        };
      };
    };
}
