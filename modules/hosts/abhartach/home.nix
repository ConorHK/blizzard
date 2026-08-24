topLevel: {
  hyprland.perHost.abhartach = ''
    hl.config({ input = { kb_layout = "us" } })
    hl.monitor({ output = "DP-1", mode = "2560x1440@144.00Hz", position = "0x0", scale = "1" })
    hl.monitor({ output = "DP-2", mode = "2560x1440@59.95Hz", position = "2560x0", scale = "1" })
    for i = 1, 8 do hl.workspace_rule({ workspace = tostring(i), monitor = "DP-1" }) end
    for i = 9, 10 do hl.workspace_rule({ workspace = tostring(i), monitor = "DP-2" }) end
  '';

  flake.modules.homeManager."homeConfigurations/abhartach" =
    { config, ... }:
    {

      age.rekey = {
        localStorageDir = ../../../.secrets/homes/abhartach;
        hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8okOt7lHfTjmabxdIruqIMxz0SwJuHSiGiC/so5IrM";
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
