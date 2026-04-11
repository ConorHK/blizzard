{ lib, ... }:
{
  options.flake.monitoringChecks = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; };
          interval = lib.mkOption {
            type = lib.types.str;
            default = "1m";
          };
          conditions = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "[STATUS] == 200" ];
          };
        };
      }
    );
  };
}
