{ ... }:
{
  flake.lib.mkRootlessContainer =
    {
      pkgs,
      name,
      image,
      cmd ? [ ],
      volumes ? [ ],
      ports ? [ ],
      environment ? { },
      extraArgs ? [ ],
      startUid,
      wantedBy ? [ "multi-user.target" ],
      after ? [ "network.target" ],
      extraServiceConfig ? { },
    }:
    let
      envArgs = map (k: "--env=${k}=${environment.${k}}") (builtins.attrNames environment);

      podmanArgs = [
        "run"
        "--rm"
        "--name"
        name
      ]
      ++ map (v: "--volume=${v}") volumes
      ++ map (p: "--publish=${p}") ports
      ++ envArgs
      ++ extraArgs
      ++ [ image ]
      ++ cmd;
    in
    {
      users.users.${name} = {
        isSystemUser = true;
        group = name;
        subUidRanges = [
          {
            startUid = startUid;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = startUid;
            count = 65536;
          }
        ];
      };
      users.groups.${name} = { };

      systemd.services."podman-${name}" = {
        description = "${name} OCI container";
        inherit wantedBy after;
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          User = name;
          RuntimeDirectory = name;
          StateDirectory = name;
          Environment = [
            "XDG_RUNTIME_DIR=/run/${name}"
            "HOME=/var/lib/${name}"
          ];
          ExecStartPre = "-${pkgs.podman}/bin/podman rm --ignore ${name}";
          ExecStart = "${pkgs.podman}/bin/podman ${pkgs.lib.escapeShellArgs podmanArgs}";
          ExecStop = "-${pkgs.podman}/bin/podman stop ${name}";
        }
        // extraServiceConfig;
      };
    };
}
