{ lib, config, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      photos = "photos.goosebox.org";
      share = "share.photos.goosebox.org";
      immich = "http://127.0.0.1:2283";
      proxy = "http://127.0.0.1:3010";
      redirect = "308 https://${share}$request_uri";

      # Immich web routes must never reach the share proxy.
      expected = {
        ${photos} = {
          "/" = immich;
          "/search" = immich;
          "/sharing" = immich;
          "/shared-links" = immich;
          "/s" = immich;
          "/share" = immich;
          "/s/abc" = redirect;
          "/share/abc" = redirect;
        };
        ${share} = {
          "/share/abc" = proxy;
          "/share/healthcheck" = proxy;
        };
      };

      # nginx picks the longest matching prefix location.
      route =
        locations: uri:
        let
          prefixes = lib.filter (name: lib.hasPrefix name uri) (lib.attrNames locations);
          best = lib.foldl' (a: b: if lib.stringLength b > lib.stringLength a then b else a) "" prefixes;
          location = locations.${best} or { };
        in
        if location.return or null != null then location.return else location.proxyPass or null;

      hosts = lib.filterAttrs (
        _: nixos:
        nixos.config.nixpkgs.hostPlatform.system == system
        && nixos.config.services.nginx.virtualHosts ? ${photos}
      ) config.flake.nixosConfigurations;

      check =
        host: nixos:
        let
          inherit (nixos.config.services.nginx) virtualHosts;
          report = lib.concatLists (
            lib.mapAttrsToList (
              vhost: uris:
              let
                locations = virtualHosts.${vhost}.locations or { };
                wrong = lib.filterAttrs (uri: want: route locations uri != want) uris;
              in
              lib.mapAttrsToList (
                uri: want: "${vhost}${uri}: want ${want}, got ${toString (route locations uri)}"
              ) wrong
            ) expected
          );
        in
        pkgs.runCommand "immich-routes-${host}" { } ''
          ${lib.concatMapStrings (line: "echo ${lib.escapeShellArg line} >&2\n") report}
          ${if report == [ ] then "touch $out" else "exit 1"}
        '';
    in
    {
      checks = lib.mapAttrs' (
        host: nixos: lib.nameValuePair "immich-routes-${host}" (check host nixos)
      ) hosts;
    };
}
