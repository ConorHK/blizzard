{ config, ... }:
{
  flake.modules.nixos."nixosConfigurations/dullahan" = config.flake.lib.mkDisko { };
}
