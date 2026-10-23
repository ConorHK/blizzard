{ config, ... }:
{
  nixosHosts.leprechaun = { };

  flake = {
    monitoringChecks.leprechaun-host = {
      name = "leprechaun";
      url = "tcp://leprechaun:443";
      interval = "1m";
      conditions = [ "[CONNECTED] == true" ];
    };

    tailnetAddresses.leprechaun = "100.91.205.65";

    modules.nixos."nixosConfigurations/leprechaun".imports = with config.flake.modules.nixos; [
      actual-budget
      arr
      arr-backup
      aqua-booking
      aqua-booking-secret
      audiobookshelf
      backup
      backup-b2
      backup-phone
      backup-secrets
      bitbang
      calibre
      changedetection
      clip
      clip-server
      dawarich
      duckdns
      freshrss
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
      prometheus
      qbittorrent
      quadlet
      readmeabook
      satisfactory
      server-users
      smartd
      syncthing-server
      systemd-boot
      tunarr
      voice
      wireguard-gateway
    ];
  };
}
