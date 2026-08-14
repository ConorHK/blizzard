{ config, ... }:
{
  flake.modules.nixos.intrusion.imports = with config.flake.modules.nixos; [
    alerts
    alerts-secret
    auth-alerts
    tripwire
  ];
}
