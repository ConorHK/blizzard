topLevel:
let
  dataDir = "/storage/data/syncthing";
in
{
  flake.monitoringChecks.syncthing = {
    name = "syncthing";
    url = "tcp://leprechaun:22000";
    conditions = [ "[CONNECTED] == true" ];
  };

  flake.modules.nixos.syncthing-server =
    { config, lib, ... }:
    {
      age.secrets.syncthing-key = {
        rekeyFile = ./secrets/key.age;
        generator.script =
          {
            pkgs,
            lib,
            file,
            ...
          }:
          let
            adjacent = name: lib.escapeShellArg (lib.removeSuffix "secrets/key.age" file + name);
          in
          ''
            home=$(mktemp -d)
            trap 'rm -rf "$home"' EXIT
            ${pkgs.syncthing}/bin/syncthing generate --home="$home" >&2
            ${pkgs.syncthing}/bin/syncthing device-id --home="$home" > ${adjacent "device-id"}
            cp "$home/cert.pem" ${adjacent "cert.pem"}
            cat "$home/key.pem"
          '';
      };

      services.syncthing = {
        enable = true;
        inherit dataDir;
        configDir = "/var/lib/syncthing";
        openDefaultPorts = true;
        cert = "${./cert.pem}";
        key = config.age.secrets.syncthing-key.path;
        settings = {
          devices = lib.mapAttrs (_: id: { inherit id; }) topLevel.config.flake.lib.syncthingDevices;
          folders.share = {
            path = "${dataDir}/share";
            devices = lib.attrNames topLevel.config.flake.lib.syncthingDevices;
          };
        };
      };
    };
}
