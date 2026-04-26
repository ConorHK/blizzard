{ config, ... }:
{
  flake.monitoringChecks.leprechaun-host = {
    name = "leprechaun";
    url = "tcp://leprechaun:443";
    interval = "1m";
    conditions = [ "[CONNECTED] == true" ];
  };

  nixosHosts.leprechaun = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    actual-budget
    audiobookshelf
    calibre
    github-nix-access
    github-runner
    immich
    mealie
    nginx
    nvidia
    podman
    qbittorrent
    quadlet
    restic
    satisfactory
    server-users
    systemd-boot
    voice
  ];
}
