topLevel: {
  flake.modules.homeManager."homeConfigurations/abhartach" =
    { config, ... }:
    {

      age = {
        rekey = {
          localStorageDir = ../../../.secrets/abhartach/goose;
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8okOt7lHfTjmabxdIruqIMxz0SwJuHSiGiC/so5IrM";
        };
        secrets = {
          cachix.rekeyFile = ./secrets/cachix.age;
          git-name.rekeyFile = ./secrets/git-name.age;
          git-email.rekeyFile = ./secrets/git-email.age;
        };
      };

      services.syncthing.settings = {
        devices.abhartach.id = "6UC67WT-CMLMJIP-JA6Z2H2-2H2ICCF-N7VRJBY-4XOMVIO-A6E7TN4-JVSW4A4";
        folders.share.devices = [ "abhartach" ];
      };

      home.sessionVariables = {
        GIT_AUTHOR_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_AUTHOR_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
        GIT_COMMITTER_NAME = "$(cat ${config.age.secrets.git-name.path})";
        GIT_COMMITTER_EMAIL = "$(cat ${config.age.secrets.git-email.path})";

        JJ_USER = "$(cat ${config.age.secrets.git-name.path})";
        JJ_EMAIL = "$(cat ${config.age.secrets.git-email.path})";

        CACHIX_AUTH_TOKEN = "$(cat ${config.age.secrets.cachix.path})";
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
        agenix
        cnvim
        desktop
        jujutsu
        ssh
        xdg
        zellij
      ];
    };
}
