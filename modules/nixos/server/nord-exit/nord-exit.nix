_: {
  flake.modules.nixos.nord-exit =
    { config, ... }:
    let
      stateDir = "${config.blizzard.storage.data}/nord-exit";
      lanAddress = config.networking.ipv4.address;
      # Host tailscaled already holds 41641.
      tailscalePort = 41642;
    in
    {
      age.secrets = {
        nord-gluetun = {
          rekeyFile = ./secrets/nord-gluetun.age;
          owner = "containers";
        };
        nord-tailscale = {
          rekeyFile = ./secrets/nord-tailscale.age;
          owner = "containers";
        };
      };

      systemd.tmpfiles.rules = [ "d ${stateDir} 0750 containers containers -" ];

      # Direct LAN path for peers, else DERP.
      networking.firewall.allowedUDPPorts = [ tailscalePort ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.nord.networkConfig = { };

        containers = {
          gluetun-nord = {
            containerConfig = {
              # renovate: datasource=docker depName=docker.io/qmcgaw/gluetun
              image = "docker.io/qmcgaw/gluetun:v3.41.3";
              addCapabilities = [ "NET_ADMIN" ];
              devices = [ "/dev/net/tun" ];
              # WIREGUARD_PRIVATE_KEY for NordLynx.
              environmentFiles = [ config.age.secrets.nord-gluetun.path ];
              publishPorts = [ "${toString tailscalePort}:${toString tailscalePort}/udp" ];
              environments = {
                VPN_SERVICE_PROVIDER = "nordvpn";
                VPN_TYPE = "wireguard";
                SERVER_COUNTRIES = "Netherlands";
                FIREWALL_INPUT_PORTS = toString tailscalePort;
                # Tailscale disco packets to LAN peers.
                FIREWALL_OUTBOUND_SUBNETS = "192.168.0.0/24";
                TZ = "Europe/Dublin";
              };
              networks = [ "nord.network" ];
            };
            # A new gluetun netns strands its clients; restart them.
            unitConfig.Upholds = "tailscale-nord.service";
          };

          tailscale-nord = {
            containerConfig = {
              # renovate: datasource=docker depName=docker.io/tailscale/tailscale
              image = "docker.io/tailscale/tailscale:v1.104.1";
              volumes = [ "${stateDir}:/var/lib/tailscale" ];
              # TS_AUTHKEY; interactive login times out.
              environmentFiles = [ config.age.secrets.nord-tailscale.path ];
              environments = {
                # Reuse saved state; key only joins once.
                TS_AUTH_ONCE = "true";
                TS_STATE_DIR = "/var/lib/tailscale";
                # No tun needed inside gluetun's netns.
                TS_USERSPACE = "true";
                TS_HOSTNAME = "leprechaun-nord";
                TS_EXTRA_ARGS = "--advertise-exit-node";
                TS_TAILSCALED_EXTRA_ARGS = "--port=${toString tailscalePort}";
                # Container sees no LAN address; advertise the host's.
                TS_DEBUG_PRETENDPOINT = "${lanAddress}:${toString tailscalePort}";
              };
              networks = [ "gluetun-nord.container" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              BindsTo = "gluetun-nord.service";
              After = "gluetun-nord.service";
            };
          };
        };
      };
    };
}
