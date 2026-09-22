{
  flake.modules.nixos.core =
    { config, lib, ... }:
    let
      quadlets = config.home-manager.users.containers.virtualisation.quadlet.containers or { };
      images =
        lib.mapAttrsToList (_: value: value.containerConfig.image) quadlets
        ++ lib.mapAttrsToList (_: value: value.image) config.virtualisation.oci-containers.containers;
    in
    {
      assertions = [
        {
          assertion = lib.all (image: builtins.match ".+@sha256:[a-f0-9]{64}" image != null) images;
          message = "Container images must use SHA256 digests.";
        }
      ];
    };
}
