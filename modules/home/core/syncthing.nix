topLevel: {
  flake.modules.homeManager.syncthing =
    { lib, ... }:
    {
      services.syncthing = {
        enable = lib.mkDefault true;
        settings = {
          devices = lib.mapAttrs (_: id: { inherit id; }) topLevel.config.flake.lib.syncthingDevices;
          folders.share = {
            path = "~/share";
            devices = lib.attrNames topLevel.config.flake.lib.syncthingDevices;
          };
        };
      };
    };
}
