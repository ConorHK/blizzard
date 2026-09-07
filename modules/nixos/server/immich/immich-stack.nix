_:
let
  # Immich runs on server, not leprechaun.
  apiUrl = "http://100.66.244.36:2283/api";
in
{
  flake.modules.nixos.immich-stack =
    { config, ... }:
    {
      age.secrets.immich-stack-secrets = {
        rekeyFile = ./secrets/immich-stack-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.immich-stack.networkConfig = { };

        containers.immich-stack.containerConfig = {
          # renovate: datasource=docker depName=docker.io/majorfi/immich-stack
          image = "docker.io/majorfi/immich-stack:0.2.43";
          # API_KEY loaded from agenix-managed env file
          environmentFiles = [ config.age.secrets.immich-stack-secrets.path ];
          environments = {
            API_URL = apiUrl;
            RUN_MODE = "cron";
            CRON_INTERVAL = "86400";
            DRY_RUN = "false";
            # JPEG wins over RAF as stack parent.
            PARENT_EXT_PROMOTE = ".jpg,.jpeg,.png,.heic,.dng";
            LOG_LEVEL = "info";
          };
          networks = [ "immich-stack.network" ];
          noNewPrivileges = true;
        };
      };
    };
}
