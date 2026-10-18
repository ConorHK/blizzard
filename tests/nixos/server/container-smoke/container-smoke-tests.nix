{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.container-smoke = pkgs.testers.runNixOSTest {
        name = "container-smoke";

        nodes.machine =
          { lib, pkgs, ... }:
          let
            image = pkgs.dockerTools.buildImage {
              name = "smoke";
              tag = "latest";
              copyToRoot = pkgs.buildEnv {
                name = "smoke-root";
                paths = [ pkgs.busybox ];
                pathsToLink = [ "/bin" ];
              };
            };

            container = exec: {
              autoStart = false;
              containerConfig = {
                image = "localhost/smoke:latest";
                inherit exec;
              };
            };

            # Fails the container unless isolation holds.
            webChecks = builtins.concatStringsSep " && " [
              "test -f /www/index.html"
              "test ! -e /www/secret/photo.jpg"
              "test -f /www/secret/.marker"
              "test -z \"$(ip -o link | grep -v ': lo:')\""
              "for _ in 1 2 3 4 5; do wget -q -O /dev/null http://db:9000/ && break; sleep 1; done"
              "wget -q -O /dev/null http://db:9000/"
              "touch /www/written"
              "exec httpd -f -p 8080 -h /www"
            ];
          in
          {
            imports = with config.flake.modules.nixos; [
              container-smoke
              podman
              quadlet
              storage
            ];

            virtualisation = {
              diskSize = 4096;
              emptyDiskImages = [ 1024 ];
            };

            boot.supportedFilesystems = [ "zfs" ];
            networking.hostId = "deadbeef";

            # Nothing pulls this in inside a test VM.
            systemd.targets.network-online.wantedBy = [ "multi-user.target" ];

            # The timer keeps the oneshot's timestamps loaded.
            system.autoUpgrade = {
              enable = true;
              flake = "/nonexistent";
              dates = "2199-12-31";
            };
            systemd.services.nixos-upgrade.script = lib.mkForce "true";

            users.users = {
              driver = {
                isNormalUser = true;
                group = "driver";
              };
              ci = {
                isSystemUser = true;
                group = "ci";
              };
            };
            users.groups = {
              driver = { };
              ci = { };
            };

            blizzard.containerSmoke = {
              requester = "ci";
              emptyPaths.web = [ "/www/secret" ];
              window = {
                start = "00:00";
                lastStart = "23:59";
              };
            };

            home-manager.users.containers.virtualisation.quadlet.containers = {
              db = container [
                "sh"
                "-c"
                "mkdir /srv && echo ok > /srv/index.html && exec httpd -f -p 9000 -h /srv"
              ];
              web =
                lib.recursiveUpdate
                  (container [
                    "sh"
                    "-c"
                    webChecks
                  ])
                  {
                    containerConfig = {
                      publishPorts = [ "127.0.0.1:8081:8080" ];
                      volumes = [ "/storage/data/web:/www" ];
                    };
                    unitConfig.Requires = "db.service";
                  };
              crash = container [ "false" ];
            };

            environment.etc."smoke-image.tar".source = image;
          };

        testScript =
          { nodes, ... }:
          let
            spec = config.flake.lib.containerSmokeSpec pkgs nodes.machine;
          in
          ''
            import json


            def smoke(run, targets):
                request = json.dumps({"spec": "${spec}", "targets": targets})
                machine.succeed(
                    f"echo '{request}' > /var/lib/container-smoke/requests/{run}.json"
                )
                return machine.execute(
                    f"su ci -s /bin/sh -c 'systemctl start container-smoke@{run}.service'"
                )[0]


            def result(run):
                return json.loads(
                    machine.succeed(f"cat /var/lib/container-smoke/results/{run}.json")
                )


            machine.wait_for_unit("multi-user.target")
            machine.wait_for_unit("user@1000.service")

            machine.succeed(
                "zpool create -O mountpoint=none storage /dev/vdb",
                "zfs create -o mountpoint=/storage/data storage/data",
                "mkdir -p /storage/data/web/secret",
                "echo hi > /storage/data/web/index.html",
                "touch /storage/data/web/secret/photo.jpg /storage/data/web/secret/.marker",
                "chown -R containers:containers /storage/data/web",
                "su containers -s /bin/sh -c "
                "'XDG_RUNTIME_DIR=/run/user/1000 podman load -i /etc/smoke-image.tar'",
            )

            with subtest("a run outside the window is deferred"):
                # Every HH:MM sorts before 24:00.
                machine.succeed(
                    "rm /etc/container-smoke/window",
                    "echo '24:00 24:00' > /etc/container-smoke/window",
                )
                assert smoke("early", ["web"]) != 0
                assert result("early")["window"]["status"] == "deferred", result("early")
                datasets = machine.succeed("zfs list -H -o name -t all")
                assert "smoke" not in datasets, datasets
                machine.succeed("echo '00:00 23:59' > /etc/container-smoke/window")

            with subtest("a healthy target passes on cloned data"):
                assert smoke("good", ["web"]) == 0
                assert result("good")["web"]["status"] == "pass", result("good")
                machine.fail("test -e /storage/data/web/written")

            with subtest("the run leaves no clones behind"):
                datasets = machine.succeed("zfs list -H -o name -t all")
                assert "smoke" not in datasets, datasets

            with subtest("a crashing target fails"):
                assert smoke("bad", ["crash"]) != 0
                assert result("bad")["crash"]["status"] == "fail", result("bad")

            with subtest("logs stay root-only"):
                machine.succeed("test -e /var/lib/container-smoke/logs/good/web.log")
                machine.fail("su ci -s /bin/sh -c 'ls /var/lib/container-smoke/logs'")

            with subtest("the requester starts nothing else"):
                machine.fail("su ci -s /bin/sh -c 'systemctl restart nix-daemon.service'")

            with subtest("a run waits for today's upgrade"):
                # The window must open after boot.
                machine.wait_until_succeeds(
                    'test $(date -d "today $(date +%H:%M)" +%s) -gt '
                    "$(($(date +%s) - $(cut -d. -f1 /proc/uptime)))"
                )
                machine.succeed('echo "$(date +%H:%M) 23:59" > /etc/container-smoke/window')
                output = machine.fail("container-smoke-window")
                assert "nixos-upgrade" in output, output
                machine.succeed("systemctl start nixos-upgrade.service")
                machine.succeed("container-smoke-window")
          '';
      };
    };
}
