{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      deployed = config.flake.nixosConfigurations.leprechaun.config;
    in
    {
      checks.selkie-isolation = pkgs.testers.runNixOSTest {
        name = "selkie-isolation";
        nodes.machine = {
          users = {
            users = {
              containers = {
                isNormalUser = true;
                uid = 1001;
                group = "containers";
              };
              selkie-nix = {
                isSystemUser = true;
                group = "selkie-nix";
              };
            };
            groups = {
              containers.gid = 987;
              selkie-nix = { };
            };
          };
          systemd = {
            tmpfiles.rules = [ "d /storage/data/selkie 0700 containers containers -" ];
            sockets.selkie-nix = {
              inherit (deployed.systemd.sockets.selkie-nix) socketConfig wantedBy;
            };
            services = {
              selkie-nix = {
                inherit (deployed.systemd.services.selkie-nix) serviceConfig requires after;
              };
              "container@selkie" = {
                requires = [ "selkie-nix.socket" ];
                after = [
                  "selkie-nix.socket"
                  "systemd-tmpfiles-setup.service"
                ];
              };
            };
          };
          containers.selkie = {
            inherit (deployed.containers.selkie) privateUsers extraFlags tmpfs;
            autoStart = true;
            config = {
              system.stateVersion = "25.05";
              systemd.services.nix-daemon.enable = false;
              systemd.sockets.nix-daemon.enable = false;
              users.users.goose = {
                isNormalUser = true;
                uid = 1001;
                group = "goose";
              };
              users.groups.goose.gid = 987;
            };
          };
        };
        testScript = ''
          machine.wait_for_unit("container@selkie.service")
          run = "nixos-container run selkie -- "
          with subtest("root uses a separate host UID"):
              leader = machine.succeed("machinectl show selkie -p Leader --value").strip()
              assert machine.succeed(f"stat -c %u /proc/{leader}").strip() == "524288"
          with subtest("home ownership needs no migration"):
              assert machine.succeed(run + "stat -c %u /home/goose").strip() == "1001"
              machine.succeed(run + "runuser -u goose -- touch /home/goose/created")
              assert machine.succeed("stat -c %u /storage/data/selkie/created").strip() == "1001"
          with subtest("only the untrusted proxy socket is exposed"):
              proxy = machine.succeed("stat -c %i /run/selkie-nix/socket").strip()
              assert machine.succeed(run + "stat -c %i /nix/var/nix/daemon-socket/socket").strip() == proxy
              out = machine.succeed(run + "nix-store --option sandbox false --add /etc/hostname 2>&1")
              assert "not a trusted user" in out, out
        '';
      };
    };
}
