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

      age = {
        rekey = {
          localStorageDir = ../../../.secrets/homes/abhartach;
          hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM8okOt7lHfTjmabxdIruqIMxz0SwJuHSiGiC/so5IrM";
        };
        secrets.mistral-api-key.rekeyFile = ./mistral-api-key.age;
      };

      home.sessionVariables = {
        JJ_USER = "$(cat ${config.age.secrets.git-name.path})";
        JJ_EMAIL = "$(cat ${config.age.secrets.git-email.path})";
      };

      programs = {
        claude-code.aperture.enable = true;

        # Mistral via its OpenAI-compatible chat API.
        pi.models.providers.mistral = {
          baseUrl = "https://api.mistral.ai/v1";
          api = "openai-completions";
          apiKey = "!cat ${config.age.secrets.mistral-api-key.path}";
          # Mistral rejects the "developer" role and the "store" field.
          compat = {
            supportsDeveloperRole = false;
            supportsStore = false;
          };
          models = [
            { id = "mistral-large-latest"; }
            { id = "devstral-medium-latest"; }
            { id = "codestral-latest"; }
          ];
        };

        waybar.settings.main.output = "DP-1";
      };

      imports = with topLevel.config.flake.modules.homeManager; [
        agenix
        cnvim
        desktop
        git-identity
        jujutsu
        ntfy
        pi
        ssh
        syncthing
        xdg
        zellij
      ];
    };
}
