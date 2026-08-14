_: {
  flake.modules.nixos.firewall-audit =
    { config, lib, ... }:
    let
      containers = config.home-manager.users.containers.virtualisation.quadlet.containers or { };

      publishedPorts = lib.concatMap (container: container.containerConfig.publishPorts or [ ]) (
        lib.attrValues containers
      );

      # "127.0.0.1:8080:80" reaches nothing from outside the host, so opening the
      # firewall for it states an intent the deployment does not have.
      loopbackOnly = lib.concatMap (
        spec:
        let
          parts = lib.splitString ":" spec;
          host = lib.elemAt parts 1;
        in
        lib.optional (
          lib.length parts == 3 && lib.hasPrefix "127." (lib.head parts) && lib.match "[0-9]+" host != null
        ) (lib.toInt host)
      ) publishedPorts;

      vestigial = lib.intersectLists loopbackOnly config.networking.firewall.allowedTCPPorts;
    in
    {
      assertions = [
        {
          assertion = vestigial == [ ];
          message =
            "firewall opens ${lib.concatMapStringsSep ", " toString vestigial}"
            + " but the containers publishing those ports bind 127.0.0.1 only";
        }
      ];
    };
}
