_:
let
  url = "music.goosebox.org";
  port = 4533;
in
{
  flake.monitoringChecks.navidrome = {
    name = "navidrome";
    url = "https://${url}/ping";
  };

  flake.modules.nixos.navidrome =
    { config, pkgs, ... }:
    let
      inherit (config.blizzard.storage) data media;
      dataDir = "${data}/navidrome";

      settings = (pkgs.formats.toml { }).generate "navidrome.toml" {
        # Defaults plus ", ", used by MusicBrainz credits.
        Tags.Artist.Split = [
          " / "
          " feat. "
          " feat "
          " ft. "
          " ft "
          "; "
          ", "
        ];
        Scanner.ArtistSplitExceptions = [
          "Tyler, The Creator"
          "Earth, Wind & Fire"
          "Crosby, Stills, Nash & Young"
          "Crosby, Stills & Nash"
        ];
      };
    in
    {
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${media}/music 0775 containers containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.navidrome.networkConfig = { };

        containers.navidrome.containerConfig = {
          # renovate: datasource=docker depName=docker.io/deluan/navidrome
          image = "docker.io/deluan/navidrome:0.64.2";
          publishPorts = [ "127.0.0.1:${toString port}:4533" ];
          volumes = [
            "${dataDir}:/data"
            "${media}/music:/music:ro"
            "${settings}:/etc/navidrome.toml:ro"
          ];
          environments = {
            TZ = "Europe/Dublin";
            ND_CONFIGFILE = "/etc/navidrome.toml";
            ND_MUSICFOLDER = "/music";
            ND_DATAFOLDER = "/data";
            ND_LISTENBRAINZ_ENABLED = "true";
            ND_DEEZER_ENABLED = "true";
            ND_ENABLEINSIGHTSCOLLECTOR = "false";
          };
          networks = [ "navidrome.network" ];
          noNewPrivileges = true;
        };
      };

      # Stopped for a consistent SQLite copy.
      restic.paths = [ dataDir ];
      restic.pauseContainers = [ "navidrome" ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          # Long FLAC streams: no buffering, no idle cutoff.
          extraConfig = ''
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
          '';
        };
      };
    };
}
