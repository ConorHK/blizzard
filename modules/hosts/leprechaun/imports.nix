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
    arr
    arr-backup
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
    gatus-watch
    glance
    github-nix-access
    github-runner
    hister
    immich
    immich-public-proxy
    immich-stack
    jellyfin
    matrix
    mealie
    nextdns
    navidrome
    nginx
    nord-exit
    nvidia
    ollama
    paperless
    photon
    pi
    podman
    podman-egress-watchdog
    qbittorrent
    quadlet
    readmeabook
    restic
    restic-secrets
    satisfactory
    selkie
    server-users
    smartd
    snoop
    syncthing-server
    systemd-boot
    tunarr
    voice
    wireguard-gateway
  ];
}
