topLevel: {
  hyprland.perHost.dullahan = ''
    hl.config({ input = { kb_layout = "gb" } })
    hl.monitor({ output = "eDP-1", mode = "1920x1080@60Hz", position = "0x0", scale = "1" })
    for i = 1, 10 do hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1" }) end
  '';

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
        tmux
        xdg
      ];
    };
}
