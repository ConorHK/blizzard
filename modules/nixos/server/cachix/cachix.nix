{
  flake.modules.nixos.cachix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cache = "conorhk";

      # The daemon waits on this hook, so only queue.
      postBuildHook = pkgs.writeShellScript "cachix-post-build-hook" ''
        for path in $OUT_PATHS; do
          case $path in
            /nix/store/*-nixos-system-*)
              name=$(${pkgs.systemd}/bin/systemd-escape "''${path#/nix/store/}")
              ${pkgs.systemd}/bin/systemctl start --no-block "cachix-push@$name.service" || true
              ;;
          esac
        done
      '';
    in
    {
      age.secrets.cachix.rekeyFile = ./secrets/cachix.age;
      environment.systemPackages = [
        pkgs.cachix
      ];

      # Push system closures from local builds.
      nix.settings.post-build-hook = postBuildHook;

      systemd.services."cachix-push@" = {
        description = "Push %I closure to Cachix";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [ config.nix.package ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          LoadCredential = "cachix-token:${config.age.secrets.cachix.path}";
          Nice = 10;
          IOSchedulingClass = "idle";
        };
        script = ''
          CACHIX_AUTH_TOKEN=$(<"$CREDENTIALS_DIRECTORY/cachix-token")
          export CACHIX_AUTH_TOKEN
          ${lib.getExe pkgs.cachix} push ${cache} "/nix/store/$1"
        '';
        scriptArgs = "%I";
      };
    };
}
