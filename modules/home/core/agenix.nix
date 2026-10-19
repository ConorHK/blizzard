{
  flake.modules.homeManager.agenix =
    {
      inputs,
      config,
      lib,
      pkgs,
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
          extraEncryptionPubkeys = [ (lib.fileContents ../../../.secrets/age-fido2-backup-recipient.pub) ];
          agePlugins = [
            pkgs.age-plugin-yubikey
            pkgs.age-plugin-fido2-hmac
          ];
          storageMode = "local";
        };
      };
    };
}
