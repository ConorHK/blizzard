{
  flake.modules.homeManager.agenix =
    {
      inputs,
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        # (lib.mkAliasOptionModule [ "secrets" ] [ "age" "secrets" ])
        inputs.agenix.homeManagerModules.default
        inputs.agenix-rekey.homeManagerModules.default
      ];

      age = {
        secretsDir = "/home/${config.home.username}/.local/share/agenix";
        secretsMountPoint = "/home/${config.home.username}/.local/share/agenix.d";

        rekey = {
          masterIdentities = [ ../../../.secrets/age-yubikey-identity.pub ];
          agePlugins = [ pkgs.age-plugin-yubikey ];
          storageMode = "local";
        };
      };
    };
}
