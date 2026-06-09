topLevel: {
  flake.modules.wrapper."hyprland/hosts/abhartach".settings = {
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

  flake.modules.homeManager."homeConfigurations/abhartach" =
    { config, ... }:
    {

      age.rekey = {
        localStorageDir = ../../../.secrets/homes/abhartach;
        hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8okOt7lHfTjmabxdIruqIMxz0SwJuHSiGiC/so5IrM";
      };

      services.syncthing.settings = {
        devices.dullahan.id = "LAIGIVW-EIN4X7E-NTWJJ7D-XE6UBDQ-LXALLB6-UR77FXM-JZJMQJ7-5TKPNAX";
        folders.share.devices = [ "dullahan" ];
      };

      home.sessionVariables = {
        JJ_USER = "$(cat ${config.age.secrets.git-name.path})";
        JJ_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };

      programs.waybar.settings.main.output = "DP-1";

      imports = with topLevel.config.flake.modules.homeManager; [
        agenix
        cnvim
        desktop
        git-identity
        jujutsu
        ntfy
        ssh
        xdg
        zellij
      ];
    };
}
