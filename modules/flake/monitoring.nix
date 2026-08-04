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
          timeout = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          # Silences this endpoint alone, unlike gatus's global `maintenance`.
          maintenanceWindows = lib.mkOption {
            default = [ ];
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  start = lib.mkOption {
                    type = lib.types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";
                  };
                  duration = lib.mkOption { type = lib.types.str; };
                  timezone = lib.mkOption {
                    type = lib.types.str;
                    default = "Europe/Dublin";
                  };
                  every = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                };
              }
            );
          };
        };
      }
    );
  };
}
