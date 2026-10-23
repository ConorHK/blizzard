{ config, ... }:
{
  flake.monitoringChecks.puca-host = {
    name = "puca";
    url = "tcp://puca:8123";
    conditions = [ "[CONNECTED] == true" ];
    # Its auto-upgrade reboot, before gatus's global window.
    maintenanceWindows = [
      {
        start = "05:00";
        duration = "70m";
      }
    ];
  };

  nixosHosts.puca = { };

  flake.modules.nixos."nixosConfigurations/puca".imports = with config.flake.modules.nixos; [
    backup
    backup-b2
    backup-secrets
    bluetooth
    github-nix-access
    grub-boot
    home-assistant
    server-users
  ];
}
