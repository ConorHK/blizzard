topLevel: {
  flake.modules.wrapper."hyprland/hosts/dullahan".settings = {
    input.kb_layout = "gb";
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

  flake.modules.homeManager."homeConfigurations/dullahan" =
    { pkgs, inputs, ... }:
    {
      home.packages = [
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.serve-here
      ];

      age = {
        rekey = {
          localStorageDir = ../../../.secrets/homes/dullahan;
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGvnibFml4dw8uL++ghBdXSCfEfb4ZDAPD6uLcXZBvWn";
        };
      };

      # services.syncthing.settings = {
      #   devices.abhartach.id = "6UC67WT-CMLMJIP-JA6Z2H2-2H2ICCF-N7VRJBY-4XOMVIO-A6E7TN4-JVSW4A4";
      #   folders.share.devices = [ "abhartach" ];
      # };

      programs.waybar.settings.main.output = "eDP-1";

      imports = with topLevel.config.flake.modules.homeManager; [
        agenix
        cnvim
        desktop
        git-identity
        laptop
        ntfy
        ssh
        xdg
        zellij
      ];
    };
}
