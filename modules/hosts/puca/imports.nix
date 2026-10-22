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
    bluetooth
    github-nix-access
    grub-boot
    home-assistant
    restic
    restic-b2
    restic-secrets
    server-users
  ];
}
