{ config, ... }:
{
  flake.monitoringChecks.leprechaun-host = {
    name = "leprechaun";
    url = "tcp://leprechaun:443";
    interval = "1m";
    conditions = [ "[CONNECTED] == true" ];
  };

  nixosHosts.leprechaun = { };

  flake.modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
    actual-budget
    aqua-booking
    aqua-booking-secret
    audiobookshelf
    calibre
    changedetection
    dawarich
    duckdns
    glance
    github-nix-access
    github-runner
    immich
    mealie
    music-assistant
    nginx
    nvidia
    photon
    podman
    qbittorrent
    quadlet
    restic
    restic-secrets
    satisfactory
    server-users
    smartd
    systemd-boot
    voice
    wireguard-gateway
  ];
}
