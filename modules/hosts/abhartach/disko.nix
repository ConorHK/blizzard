{ config, ... }:
{
  flake.modules.nixos."nixosConfigurations/abhartach" = config.flake.lib.mkDisko {
    fido2 = true;
  };
}
