{
  flake.modules.nixos.tsidp =
    { lib, ... }:
    {
      virtualisation.oci-containers = {
        backend = lib.mkDefault "podman";

        containers.tsidp = {
          image = "ghcr.io/tailscale/tailscale:latest";
          autoStart = true;

          volumes = [
            "/var/lib/tailscale-tsidp:/var/lib/tailscale"
            "/dev/net/tun:/dev/net/tun"
          ];

          # Set additional environment variables
          environment = {
            TS_ACCEPT_DNS = "true";
            TS_AUTH_ONCE = "true";
            TS_USERSPACE = "false";
            TAILSCALE_USE_WIP_CODE = "1";
          };

          extraOptions = [
            "--network=host"
            "--device=/dev/net/tun:/dev/net/tun"
            "--cap-add=NET_ADMIN"
            "--cap-add=NET_RAW"
            "--cap-add=SYS_MODULE"
          ];
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/tailscale-tsidp 0755 root root"
      ];
    };
}
