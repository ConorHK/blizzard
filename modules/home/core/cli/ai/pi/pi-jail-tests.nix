{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.pi-jail = pkgs.testers.runNixOSTest {
        name = "pi-jail";

        nodes = {
          server = {
            networking.firewall.allowedTCPPorts = [ 80 ];
            systemd.services.web = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 80 --directory /etc";
            };
          };

          machine =
            { pkgs, ... }:
            let
              # Stands in for pi: runs its arguments.
              stub = pkgs.writeShellScriptBin "pi" ''exec "$@"'';
            in
            {
              imports = [ config.flake.modules.nixos.pi ];

              users.users.alice.isNormalUser = true;
              # Like goose: trusted outside the jail.
              nix.settings.trusted-users = [ "alice" ];
              systemd.tmpfiles.rules = [ "d /home/alice/work 0755 alice users -" ];

              environment.systemPackages = [
                (config.flake.lib.mkPiJail pkgs { package = stub; })
                pkgs.curl
                pkgs.iproute2
                pkgs.python3
                pkgs.socat
              ];
            };
        };

        testScript = ''
          import shlex


          def as_alice(cmd):
              return machine.succeed(f"su - alice -c {shlex.quote(cmd)}")


          def jailed(cmd):
              return as_alice(f"cd ~/work && pi-jail sh -c {shlex.quote(cmd)}")


          start_all()
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("pi-nix-daemon.socket")
          server.wait_for_open_port(80)

          with subtest("the daemon trusts alice but not the jail"):
              probe = "nix --extra-experimental-features nix-command store info 2>&1"
              assert "Trusted: 1" in as_alice(probe)
              out = jailed(probe)
              assert "Trusted: 0" in out, out

          with subtest("host abstract sockets stay outside"):
              machine.succeed(
                  "systemd-run -p User=alice --unit probe-abstract "
                  "socat ABSTRACT-LISTEN:pi-jail-probe,fork EXEC:true"
              )
              machine.wait_until_succeeds("grep -q @pi-jail-probe /proc/net/unix")
              out = jailed("grep -c @pi-jail-probe /proc/net/unix || true")
              assert out.strip() == "0", out

          with subtest("host loopback services stay outside"):
              machine.succeed(
                  "systemd-run --unit probe-loopback "
                  "python3 -m http.server 8999 --bind 127.0.0.1"
              )
              machine.wait_for_open_port(8999)
              out = jailed(
                  "gw=$(ip route | awk '/default/ {print $3}'); "
                  "for host in 127.0.0.1 $gw; do "
                  "curl -s --max-time 5 -o /dev/null http://$host:8999 "
                  "&& echo open $host || echo closed $host; done"
              )
              # Loopback and the mapped gateway.
              assert out.count("closed") == 2 and "open" not in out, out

          with subtest("the network still reaches other hosts"):
              jailed("curl -sf --max-time 30 -o /dev/null http://server/hostname")

          with subtest("/run holds only what the jail restores"):
              entries = set(jailed("ls -A /run").split())
              assert entries <= {"current-system", "user"}, entries
        '';
      };
    };
}
