{ inputs, ... }:
{
  flake.modules.nixos.agenix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        (lib.mkAliasOptionModule [ "secrets" ] [ "age" "secrets" ])
        inputs.agenix.nixosModules.default
        inputs.agenix-rekey.nixosModules.default
      ];

      environment.systemPackages = [ pkgs.rage ];

      age.rekey = {
        storageMode = "local";
        masterIdentities = [ ../../../.secrets/age-yubikey-identity.pub ];
        extraEncryptionPubkeys = [ (lib.fileContents ../../../.secrets/age-fido2-backup-recipient.pub) ];
        agePlugins = [
          pkgs.age-plugin-yubikey
          pkgs.age-plugin-fido2-hmac
        ];
        localStorageDir = ../../../.secrets/${config.networking.hostName};
      };
    };
}
