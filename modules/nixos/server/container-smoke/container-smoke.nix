{ config, lib, ... }:
let
  # Container port of the first TCP publish.
  tcpPort =
    publish:
    let
      parts = lib.splitString "/" publish;
      proto = if lib.length parts > 1 then lib.elemAt parts 1 else "tcp";
    in
    if proto == "tcp" then lib.toInt (lib.last (lib.splitString ":" (lib.head parts))) else null;

  volume =
    spec:
    let
      parts = lib.splitString ":" spec;
    in
    {
      host = lib.elemAt parts 0;
      target = lib.elemAt parts 1;
      readOnly = lib.length parts > 2 && lib.elem "ro" (lib.splitString "," (lib.elemAt parts 2));
    };

  words =
    value: lib.filter (word: word != "") (lib.concatMap (lib.splitString " ") (lib.toList value));

  # Building the spec realises its store paths.
  mkSpec =
    pkgs: hostConfig:
    let
      inherit (hostConfig.blizzard) containerSmoke;
      containers = hostConfig.home-manager.users.containers.virtualisation.quadlet.containers;

      requires =
        unit:
        lib.pipe
          [ "Requires" "BindsTo" ]
          [
            (lib.concatMap (key: words (unit.${key} or [ ])))
            (map (lib.removeSuffix ".service"))
            (lib.filter (name: containers ? ${name}))
          ];

      entry =
        name: container:
        let
          c = container.containerConfig;
        in
        {
          inherit (c) image;
          requires = requires container.unitConfig;
          port = lib.findFirst (port: port != null) null (map tcpPort (c.publishPorts or [ ]));
          volumes = map volume (c.volumes or [ ]);
          environments = c.environments or { };
          environmentFiles = c.environmentFiles or [ ];
          exec =
            if (c.exec or null) == null then
              null
            else if lib.isList c.exec then
              c.exec
            else
              words c.exec;
          entrypoint = c.entrypoint or null;
          user = c.user or null;
          userns = c.userns or null;
          addCapabilities = c.addCapabilities or [ ];
          shmSize = c.shmSize or null;
          noNewPrivileges = c.noNewPrivileges or false;
          emptyPaths = containerSmoke.emptyPaths.${name} or [ ];
        };
    in
    pkgs.writeText "container-smoke.json" (builtins.toJSON (lib.mapAttrs entry containers));
in
{
  flake = {
    lib.containerSmokeSpec = mkSpec;
    containerSmoke = lib.mapAttrs (_: host: mkSpec host.pkgs host.config) (
      lib.filterAttrs (_: host: host.config.blizzard ? containerSmoke) config.flake.nixosConfigurations
    );

    modules.nixos.container-smoke =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.blizzard.containerSmoke;
        stateDir = "/var/lib/container-smoke";

        # Duplicate containers starve production; gatus is silent then.
        window = pkgs.writeShellApplication {
          name = "container-smoke-window";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.systemd
          ];
          runtimeEnv.UPGRADES = lib.boolToString config.system.autoUpgrade.enable;
          text = builtins.readFile ./window.sh;
        };

        run = pkgs.writeShellApplication {
          name = "container-smoke";
          runtimeInputs = [
            window
            config.boot.zfs.package
            config.virtualisation.podman.package
            pkgs.coreutils
            pkgs.curl
            pkgs.findutils
            pkgs.gawk
            pkgs.iproute2
            pkgs.jq
            pkgs.util-linux
          ];
          runtimeEnv = {
            STATE_DIR = stateDir;
            DATASET = cfg.dataset;
            DATA_DIR = config.blizzard.storage.data;
          };
          text = builtins.readFile ./run.sh;
        };
      in
      {
        options.blizzard.containerSmoke = {
          dataset = lib.mkOption {
            type = lib.types.str;
            default = "storage/data";
            description = "ZFS dataset mounted at the data root.";
          };

          requester = lib.mkOption {
            type = lib.types.str;
            description = "User allowed to start smoke tests.";
          };

          windowCheck = lib.mkOption {
            type = lib.types.package;
            readOnly = true;
            default = window;
            description = "Exits 0 when a smoke run may start.";
          };

          window = {
            start = lib.mkOption {
              type = lib.types.strMatching "[0-2][0-9]:[0-5][0-9]";
              default = "06:00";
              description = "Local time smoke runs may start from; the upgrade window.";
            };
            lastStart = lib.mkOption {
              type = lib.types.strMatching "[0-2][0-9]:[0-5][0-9]";
              default = "06:40";
              description = "Latest start; a 30m run ends before gatus alerts at 07:10.";
            };
          };

          emptyPaths = lib.mkOption {
            type = lib.types.attrsOf (lib.types.listOf lib.types.str);
            default = { };
            description = "Container paths left empty in smoke tests, per container.";
          };
        };

        config = {
          environment.systemPackages = [ window ];
          # A file, so tests can close it.
          environment.etc."container-smoke/window".text = "${cfg.window.start} ${cfg.window.lastStart}\n";

          systemd.tmpfiles.rules = [
            "d ${stateDir} 0711 root root -"
            "d ${stateDir}/requests 0700 ${cfg.requester} ${cfg.requester} 7d"
            "d ${stateDir}/results 0755 root root 7d"
            # Logs hold app data, kept off CI.
            "d ${stateDir}/logs 0700 root root 14d"
            "d ${stateDir}/runs 0711 root root -"
          ];

          systemd.services."container-smoke@" = {
            description = "Smoke test containers for %i";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe run} %i";
              TimeoutStartSec = "30min";
            };
          };

          security.polkit = {
            enable = true;
            extraConfig = ''
              polkit.addRule(function (action, subject) {
                if (action.id == "org.freedesktop.systemd1.manage-units" &&
                    subject.user == "${cfg.requester}" &&
                    action.lookup("verb") == "start" &&
                    /^container-smoke@[0-9a-z-]+\.service$/.test(action.lookup("unit"))) {
                  return polkit.Result.YES;
                }
              });
            '';
          };
        };
      };
  };
}
