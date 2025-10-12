topLevel: {
  flake.modules.homeManager."homeConfigurations/abhartach" =
    { config, ... }:
    {

      age = {
        rekey = {
          localStorageDir = ../../../.secrets/abhartach/goose;
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8okOt7lHfTjmabxdIruqIMxz0SwJuHSiGiC/so5IrM";
        };
        secrets.git-name.rekeyFile = ./git-name.age;
        secrets.git-email.rekeyFile = ./git-email.age;
      };

      home.sessionVariables = {
        GIT_AUTHOR_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_AUTHOR_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
        GIT_COMMITTER_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_COMMITTER_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };

      programs.waybar.settings.main.output = "DP-1";
      wayland.windowManager.hyprland.settings = {
        workspace = [
          "1,monitor:DP-1"
          "2,monitor:DP-1"
          "3,monitor:DP-1"
          "4,monitor:DP-1"
          "5,monitor:DP-1"
          "6,monitor:DP-1"
          "7,monitor:DP-1"
          "8,monitor:DP-1"
          "9,monitor:DP-2"
          "10,monitor:DP-2"
        ];
        monitor = [
          "DP-1,2560x1440@144.00Hz,0x0,1"
          "DP-2,2560x1440@59.95Hz,2560x0,1"
        ];
      };

      imports = with topLevel.config.flake.modules.homeManager; [
        desktop
        xdg
        agenix
      ];
    };
}
