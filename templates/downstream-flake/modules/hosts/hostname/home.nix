topLevel: {
  flake.modules.homeManager."homeConfigurations/hostname" =
    { inputs, ... }:
    {
      age.rekey = {
        localStorageDir = ../../../.secrets/hostname/username;
        hostPubkey = "ssh-ed25519 PUBKEY";
      };

      imports = [
        inputs.blizzard.modules.homeManager.agenix
        inputs.blizzard.modules.homeManager.cnvim
        inputs.blizzard.modules.homeManager.core
        inputs.blizzard.modules.homeManager.xdg
        inputs.blizzard.modules.homeManager.zellij
      ];
    };
}
