_: {
  flake.modules.nixos.boinc =
    { config, ... }:
    {
      age.secrets.boinc-secrets = {
        rekeyFile = ./secrets/boinc-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        containers.boinc.containerConfig = {
          # renovate: datasource=docker depName=boinc/client
          image = "boinc/client:latest";
          volumes = [ "/storage/data/boinc:/var/lib/boinc" ];
          # BOINC_GUI_RPC_PASSWORD loaded from agenix-managed env file
          environmentFiles = [ config.age.secrets.boinc-secrets.path ];
          environment = {
            BOINC_CMD_LINE_OPTIONS = "--allow_remote_gui_rpc";
          };
          # Uses host networking like original docker-compose network_mode: host
          networkMode = "host";
          # pid=host required for BOINC client to work correctly
          podmanArgs = "--pid=host";
        };
      };
    };
}
