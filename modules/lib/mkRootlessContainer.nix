{ lib, ... }:
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
      extraGroups ? [ ],
      startUid,
      after ? [
        "network.target"
        "network-online.target"
      ],
      wants ? [ "network-online.target" ],
      extraServiceConfig ? { },
    }:
    let
      enableFile = "/var/lib/${name}/.enabled";

      logsScript = pkgs.writeShellScriptBin "${name}-logs" ''
        exec ${pkgs.systemd}/bin/journalctl -u "podman-${name}" "$@"
      '';

      envArgs = map (k: "--env=${k}=${environment.${k}}") (builtins.attrNames environment);

      podmanArgs = [
        "run"
        "--rm"
        "--name"
        name
        "--cgroup-manager=cgroupfs"
        "--no-healthcheck"
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
        inherit extraGroups;
        subUidRanges = [
          {
            inherit startUid;
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

      environment.systemPackages = [ logsScript ];

      environment.etc = {
        "subuid" = {
          mode = "0644";
          text = "${name}:${toString startUid}:65536\n";
        };
        "subgid" = {
          mode = "0644";
          text = "${name}:${toString startUid}:65536\n";
        };
      };

      systemd.services."podman-${name}" = {
        description = "${name} OCI container";
        wantedBy = [ "multi-user.target" ];
        inherit after wants;
        serviceConfig = lib.mkMerge [
          {
            Type = "simple";
            Restart = "always";
            User = name;
            RuntimeDirectory = name;
            StateDirectory = name;
            Environment = [
              "XDG_RUNTIME_DIR=/run/${name}"
              "HOME=/var/lib/${name}"
              "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
            ];
            ConditionPathExists = enableFile;
            ExecStartPre = "-${pkgs.podman}/bin/podman rm --ignore ${name}";
            ExecStart = "${pkgs.podman}/bin/podman ${pkgs.lib.escapeShellArgs podmanArgs}";
            ExecStop = "-${pkgs.podman}/bin/podman stop ${name}";
            ExecStartPost = "${pkgs.coreutils}/bin/touch ${enableFile}";
          }
          extraServiceConfig
        ];
      };
    };
}
