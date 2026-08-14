_: {
  flake.modules.nixos.monitoring-coverage =
    {
      config,
      lib,
      monitoringChecks,
      ...
    }:
    let
      cfg = config.blizzard.monitoring;

      # Only public names: the catch-all and localhost vhosts have nothing to watch.
      published = lib.filter (name: lib.hasInfix "." name) (
        lib.attrNames (lib.filterAttrs (_: vhost: !vhost.default) config.services.nginx.virtualHosts)
      );

      unmonitored = lib.filter (
        name:
        !(lib.elem name cfg.exempt) && !(lib.any (check: lib.hasInfix name check.url) monitoringChecks)
      ) published;
    in
    {
      options.blizzard.monitoring.exempt = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Virtual hosts deliberately left without a monitoring check.";
      };

      config.assertions = [
        {
          assertion = unmonitored == [ ];
          message =
            "no monitoringChecks entry covers ${lib.concatStringsSep ", " unmonitored}"
            + " — add one, or list it in blizzard.monitoring.exempt";
        }
      ];
    };
}
