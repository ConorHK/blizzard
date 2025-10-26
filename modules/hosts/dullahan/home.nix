topLevel: {
  flake.modules.homeManager."homeConfigurations/dullahan" =
    { config, ... }:
    {

      age = {
        rekey = {
          localStorageDir = ../../../.secrets/dullahan/goose;
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvnibFml4dw8uL++ghBdXSCfEfb4ZDAPD6uLcXZBvWn";
        };
      };

      # services.syncthing.settings = {
      #   devices.abhartach.id = "6UC67WT-CMLMJIP-JA6Z2H2-2H2ICCF-N7VRJBY-4XOMVIO-A6E7TN4-JVSW4A4";
      #   folders.share.devices = [ "abhartach" ];
      # };

      home.sessionVariables = {
        GIT_AUTHOR_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_AUTHOR_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
        GIT_COMMITTER_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_COMMITTER_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };

      programs.waybar.settings.main.output = "eDP-1";
      wayland.windowManager.hyprland.settings = {
        workspace = [
          "1,monitor:eDP-1"
          "2,monitor:eDP-1"
          "3,monitor:eDP-1"
          "4,monitor:eDP-1"
          "5,monitor:eDP-1"
          "6,monitor:eDP-1"
          "7,monitor:eDP-1"
          "8,monitor:eDP-1"
          "9,monitor:eDP-1"
          "10,monitor:eDP-1"
        ];
        monitor = [
          "eDP-1,1920x1080@60Hz,0x0,1"
        ];
      };

      imports = with topLevel.config.flake.modules.homeManager; [
        agenix
        cnvim
        desktop
        ntfy
        ssh
        xdg
        zellij
      ];
    };
}
