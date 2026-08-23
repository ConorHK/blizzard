{
  flake.modules.nixos.core =
    { lib, ... }:
    {
      options.networking = {
        # Metadata only; consumed by the ssh `-local` host aliases, not by any interface config.
        ipv4.address = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "[0-9]{1,3}(\\.[0-9]{1,3}){3}");
          default = null;
        };
        ipv4.prefixLength = lib.mkOption {
          type = lib.types.int;
          default = 24;
        };
      };
    };
}
