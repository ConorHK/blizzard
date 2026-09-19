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
    bitbang
    calibre
    changedetection
    clip
    clip-server
    dawarich
    duckdns
    glance
    github-nix-access
    github-runner
    hister
    immich
    immich-public-proxy
    immich-stack
    matrix
    mealie
    music-assistant
    nextdns
    nginx
    nvidia
    photon
    pi
    podman
    podman-egress-watchdog
    qbittorrent
    quadlet
    restic
    restic-secrets
    satisfactory
    selkie
    server-users
    smartd
    snoop
    syncthing-server
    systemd-boot
    voice
    wireguard-gateway
  ];
}
