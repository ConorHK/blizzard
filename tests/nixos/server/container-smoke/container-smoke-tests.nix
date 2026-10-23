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

            # Turns the gate on.
            system.autoUpgrade = {
              enable = true;
              flake = "/nonexistent";
              dates = "2199-12-31";
            };
            systemd.services.nixos-upgrade.script = lib.mkForce "sleep 600";

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
              createPaths.media = [
                "/data/app/downloads"
                "/www/secret/made"
              ];
              skip = [ "online" ];
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
              # Needs dirs a blanked volume lacks.
              media =
                lib.recursiveUpdate
                  (container [
                    "sh"
                    "-c"
                    "test -d /data/app/downloads && test -d /www/secret/made && touch /data/app/downloads/x && exec sleep 600"
                  ])
                  {
                    containerConfig.volumes = [
                      "/storage/media:/data"
                      "/storage/data/web:/www"
                    ];
                  };
              # Would fail; skipped instead.
              online = container [ "false" ];
              # Answers one connection, then restarts.
              flap = lib.recursiveUpdate (container [
                "sh"
                "-c"
                "mkdir /srv && nc -l -p 8080 -e true && sleep 3 && exec httpd -f -p 8080 -h /srv"
              ]) { containerConfig.publishPorts = [ "127.0.0.1:8082:8080" ]; };
            }
            # Both bind 7000, like two instances of one app.
            // lib.genAttrs [ "twin-a" "twin-b" ] (
              _:
              lib.recursiveUpdate (container [
                "sh"
                "-c"
                "mkdir /srv && exec httpd -f -p 7000 -h /srv"
              ]) { containerConfig.publishPorts = [ "127.0.0.1:7000:7000" ]; }
            );

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

            with subtest("a run before a pending reboot is deferred"):
                machine.succeed("touch /run/systemd/shutdown/scheduled")
                assert smoke("early", ["web"]) != 0
                assert result("early")["gate"]["status"] == "deferred", result("early")
                datasets = machine.succeed("zfs list -H -o name -t all")
                assert "smoke" not in datasets, datasets
                machine.succeed("rm /run/systemd/shutdown/scheduled")

            with subtest("a healthy target passes on cloned data"):
                assert smoke("good", ["web"]) == 0
                assert result("good")["web"]["status"] == "pass", result("good")
                machine.fail("test -e /storage/data/web/written")

            with subtest("the run leaves no clones behind"):
                datasets = machine.succeed("zfs list -H -o name -t all")
                assert "smoke" not in datasets, datasets

            with subtest("a port that drops during startup passes"):
                assert smoke("flap", ["flap"]) == 0, result("flap")
                assert result("flap")["flap"]["status"] == "pass", result("flap")

            with subtest("unrelated targets on one port both pass"):
                assert smoke("twins", ["twin-a", "twin-b"]) == 0, result("twins")
                assert result("twins")["twin-a"]["status"] == "pass", result("twins")
                assert result("twins")["twin-b"]["status"] == "pass", result("twins")

            with subtest("a skipped target passes untested"):
                assert smoke("skip", ["online"]) == 0, result("skip")
                assert result("skip")["online"]["status"] == "pass", result("skip")
                assert smoke("mixed", ["online", "crash"]) != 0, result("mixed")
                assert result("mixed")["online"]["status"] == "pass", result("mixed")
                assert result("mixed")["crash"]["status"] == "fail", result("mixed")

            with subtest("created paths exist only inside the run"):
                assert smoke("create", ["media"]) == 0, result("create")
                assert result("create")["media"]["status"] == "pass", result("create")
                machine.fail("test -e /storage/media/app")
                machine.fail("test -e /storage/data/web/secret/made")

            with subtest("a crashing target fails"):
                assert smoke("bad", ["crash"]) != 0
                assert result("bad")["crash"]["status"] == "fail", result("bad")

            with subtest("logs stay root-only"):
                machine.succeed("test -e /var/lib/container-smoke/logs/good/web.log")
                machine.fail("su ci -s /bin/sh -c 'ls /var/lib/container-smoke/logs'")

            with subtest("the requester starts nothing else"):
                machine.fail("su ci -s /bin/sh -c 'systemctl restart nix-daemon.service'")

            with subtest("a run waits for a running upgrade"):
                machine.succeed("container-smoke-gate")
                machine.succeed("systemctl start --no-block nixos-upgrade.service")
                machine.wait_until_fails("container-smoke-gate")
                output = machine.fail("container-smoke-gate")
                assert "nixos-upgrade" in output, output
                machine.succeed("systemctl stop nixos-upgrade.service")
                machine.succeed("container-smoke-gate")

            with subtest("a run waits for an upgrade due soon"):
                dropin = "/run/systemd/system/nixos-upgrade.timer.d"
                machine.succeed(
                    f"mkdir -p {dropin}",
                    "printf '[Timer]\\nOnCalendar=\\nOnCalendar=%s\\n' "
                    f"\"$(date -d '+10 min' '+%F %H:%M:00')\" > {dropin}/soon.conf",
                    "systemctl daemon-reload",
                    "systemctl restart nixos-upgrade.timer",
                )
                output = machine.fail("container-smoke-gate")
                assert "starts within" in output, output
                machine.succeed(
                    f"rm -r {dropin}",
                    "systemctl daemon-reload",
                    "systemctl restart nixos-upgrade.timer",
                )
                machine.succeed("container-smoke-gate")
          '';
      };
    };
}
