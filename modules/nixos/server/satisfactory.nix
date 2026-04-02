{
  flake.modules.nixos.satisfactory =
    { pkgs, blizzardLib, ... }:
    let
      # renovate: datasource=docker depName=ghcr.io/wolveix/satisfactory-server
      satisfactoryVersion = "v1.9.10";
      dataDir = "/storage/service/satisfactory-server/data";
    in
    blizzardLib.mkRootlessContainer {
      inherit pkgs;
      name = "satisfactory";
      image = "ghcr.io/wolveix/satisfactory-server:${satisfactoryVersion}";
      startUid = 100000;
      volumes = [ "${dataDir}:/config" ];
      ports = [
        "7777:7777/tcp"
        "7777:7777/udp"
        "8888:8888/tcp"
      ];
      environment = {
        AUTOPAUSE = "false";
        AUTOSAVE = "true";
        AUTOSAVENUM = "3";
        AUTOSAVEINTERVAL = "300";
        MAXPLAYERS = "8";
      };
    };
}
