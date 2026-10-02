{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.selkie-isolation = pkgs.testers.runNixOSTest {
        name = "selkie-isolation";

        nodes.machine = {
          virtualisation = {
            memorySize = 2048;
            # nspawn idmaps /nix/store; virtiofs cannot.
            useNixStoreImage = true;
            writableStore = false;
          };

          systemd.tmpfiles.rules = [
            # Host uid and gid of `containers`.
            "d /srv/selkie 0700 1001 987 -"
            # A read-only store image ships no db.
            "d /nix/var/nix/db 0755 root root -"
          ];

          containers.test = config.flake.lib.selkieIsolation "/srv/selkie" // {
            autoStart = true;
            # Slow CI hosts boot past the 1min default.
            timeoutStartSec = "10min";
            hostAddress = "10.111.0.1";
            localAddress = "10.111.0.2";

            config =
              { pkgs, ... }:
              {
                # selkie borrows the host daemon.
                systemd = {
                  services.nix-daemon.enable = false;
                  sockets.nix-daemon.enable = false;
                };

                users = {
                  users.goose = {
                    isNormalUser = true;
                    uid = 1001;
                    group = "goose";
                    extraGroups = [ "wheel" ];
                  };
                  groups.goose.gid = 987;
                };
                security.sudo.wheelNeedsPassword = false;

                environment.systemPackages = [
                  pkgs.bindfs
                  pkgs.iproute2
                ];

                system.stateVersion = "25.05";
              };
          };
        };

        testScript = ''
          def inside(cmd):
              return machine.succeed(f"nixos-container run test -- sh -c {cmd!r}")

          machine.wait_for_unit("container@test.service")
          machine.wait_until_succeeds(
              "nixos-container run test -- test -x /run/wrappers/bin/sudo", timeout=300
          )

          with subtest("container root is not host root"):
              leader = machine.succeed("machinectl show test -p Leader --value").strip()
              uid = machine.succeed(f"stat -c %u /proc/{leader}").strip()
              assert uid != "0", f"container init runs as host uid {uid}"

          # Accept logs trust before opening the store.
          def daemon_accepts():
              return machine.succeed(
                  "journalctl -u nix-daemon.service -o cat | grep 'accepted connection' || true"
              ).splitlines()

          probe = "nix --extra-experimental-features nix-command --store daemon store info >&2 || true"

          with subtest("the host daemon does not trust container root"):
              machine.succeed(probe)
              host = daemon_accepts()[-1]
              assert "(trusted)" in host, host
              inside(probe)
              container = daemon_accepts()[-1]
              assert container != host and "(trusted)" not in container, container

          with subtest("the idmapped home stays owned by host uid 1001"):
              inside("runuser -u goose -- touch /home/goose/probe")
              owner = machine.succeed("stat -c %u:%g /srv/selkie/probe").strip()
              assert owner == "1001:987", owner

          with subtest("goose keeps sudo inside the container"):
              inside("runuser -u goose -- /run/wrappers/bin/sudo -n true")

          with subtest("tailscale's tun and bitbang's fuse still work"):
              inside("ip tuntap add dev tun0 mode tun")
              inside("mkdir -p /tmp/a /tmp/b && bindfs -r /tmp/a /tmp/b && mountpoint -q /tmp/b")
        '';
      };
    };
}
