{ config, ... }:
{
  flake.modules.nixos.network.imports = with config.flake.modules.nixos; [
    firewall-audit
    monitoring-coverage
    network-manager
    ssh
    tailscale
  ];
}
