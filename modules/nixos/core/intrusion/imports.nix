{ config, ... }:
{
  flake.modules.nixos.intrusion.imports = with config.flake.modules.nixos; [
    alerts
    auth-alerts
    tripwire
  ];
}
