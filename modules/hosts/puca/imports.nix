{ config, ... }:
let
  # Its auto-upgrade reboot, before gatus's global window.
  rebootWindow = [
    {
      start = "05:00";
      duration = "70m";
    }
  ];
in
{
  nixosHosts.puca = { };

  flake = {
    monitoringChecks = {
      puca-host = {
        name = "puca";
        url = "tcp://puca:8123";
        conditions = [ "[CONNECTED] == true" ];
        maintenanceWindows = rebootWindow;
      };
      home-assistant.maintenanceWindows = rebootWindow;
    };

    tailnetAddresses.puca = "100.95.121.34";

    modules.nixos."nixosConfigurations/puca".imports = with config.flake.modules.nixos; [
      backup
      backup-b2
      backup-secrets
      bluetooth
      github-nix-access
      grub-boot
      home-assistant
      nginx
      podman
      server-users
    ];
  };
}
