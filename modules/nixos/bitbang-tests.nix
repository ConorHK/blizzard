{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.bitbang = pkgs.testers.runNixOSTest {
        name = "bitbang";

        nodes.machine =
          { lib, pkgs, ... }:
          {
            imports = [ config.flake.modules.nixos.bitbang ];

            # Stands in for the real CLI: it never reaches the network, and it
            # reports what the wrapper handed it, as whom.
            blizzard.bitbang.package = pkgs.writeShellScriptBin "bitbang" ''
              report=/tmp/report
              {
                echo "USER=$(id -un)"
                echo "GROUPS=$(id -Gn)"
                echo "ARGV=$*"
              } >"$report"

              if [ "''${1:-}" = serve ] && [ "''${2:-}" = files ]; then
                mp=$3
                {
                  for f in "$mp/secret.txt" "$mp/files/secret.txt"; do
                    if [ -e "$f" ]; then
                      echo "READ=$(cat "$f" 2>&1)"
                    fi
                  done
                  for d in "$mp" "$mp/files" "$mp/upload"; do
                    if [ ! -d "$d" ]; then
                      continue
                    fi
                    if echo dropped >"$d/probe.txt" 2>/dev/null; then
                      echo "WRITABLE=$d"
                    else
                      echo "READONLY=$d"
                    fi
                  done
                } >>"$report" 2>&1
              fi

              chmod 0644 "$report"
            '';

            blizzard.bitbang.shareMembers = [ "tester" ];

            users.users.tester = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
            };

            security.sudo.wheelNeedsPassword = lib.mkForce false;

            # bindfs needs the module; nothing else in the VM pulls it in.
            boot.kernelModules = [ "fuse" ];
          };

        testScript = ''
          SHARE = "/srv/share"


          def as_tester(command):
              return machine.succeed(f"su tester -s /bin/sh -c {command!r}")


          def report():
              out = machine.succeed("cat /tmp/report")
              return dict(
                  line.split("=", 1) for line in out.strip().splitlines() if "=" in line
              )


          def sessions():
              return machine.succeed(
                  "ls /run/bitbang 2>/dev/null | wc -l"
              ).strip()


          machine.wait_for_unit("multi-user.target")

          machine.succeed(f"mkdir -p {SHARE}")
          machine.succeed(f"echo topsecret > {SHARE}/secret.txt")
          # Unreadable to anyone but root: the view has to grant the access.
          machine.succeed(f"chmod 600 {SHARE}/secret.txt")

          with subtest("the upload directory is shared, not world-writable"):
              machine.succeed("test -d /upload")
              mode = machine.succeed("stat -c %a:%U:%G /upload").strip()
              assert mode == "2770:root:bitbang-share", mode
              acl = machine.succeed("getfacl -p /upload")
              assert "default:group:bitbang-share:rwx" in acl, acl

          with subtest("serve runs as the service account, never the caller"):
              as_tester(f"bitbang serve files {SHARE}")
              r = report()
              assert r["USER"] == "bitbang", r
              assert "bitbang-share" in r["GROUPS"], r

          with subtest("the view grants read access to a 0600 file"):
              assert report()["READ"] == "topsecret", report()

          with subtest("defaults are injected for serve"):
              argv = report()["ARGV"]
              assert "-ephemeral" in argv, argv
              assert "-pin" in argv, argv

          with subtest("the served path is the view, not the real directory"):
              argv = report()["ARGV"].split()
              assert argv[2].startswith("/run/bitbang/"), argv
              assert SHARE not in argv, argv

          with subtest("without -upload the whole view is read-only"):
              assert "READONLY" in report(), report()
              assert "WRITABLE" not in report(), report()
              machine.succeed(f"test ! -e {SHARE}/probe.txt")

          with subtest("the session is torn down when serve exits"):
              assert sessions() == "0", machine.succeed("ls -la /run/bitbang")

          with subtest("-upload writes land in /upload and nowhere else"):
              machine.succeed("rm -f /upload/probe.txt")
              as_tester(f"bitbang serve files {SHARE} -upload")
              r = report()
              assert r["READ"] == "topsecret", r
              assert r["READONLY"].endswith("/files"), r
              assert r["WRITABLE"].endswith("/upload"), r
              assert machine.succeed("cat /upload/probe.txt").strip() == "dropped"
              machine.succeed(f"test ! -e {SHARE}/probe.txt")
              assert sessions() == "0", machine.succeed("ls -la /run/bitbang")

          with subtest("a share member can rewrite what bitbang uploaded"):
              owner = machine.succeed("stat -c %U:%G /upload/probe.txt").strip()
              assert owner == "bitbang:bitbang-share", owner
              as_tester("echo edited > /upload/probe.txt")
              assert machine.succeed("cat /upload/probe.txt").strip() == "edited"

          with subtest("shell forms get a pinned shell, file forms do not"):
              as_tester("bitbang serve shell")
              assert "-shell-cmd" in report()["ARGV"], report()

              as_tester(f"bitbang serve files {SHARE}")
              assert "-shell-cmd" not in report()["ARGV"], report()

          with subtest("non-serve subcommands are passed through untouched"):
              as_tester("bitbang connect device1")
              argv = report()["ARGV"]
              assert argv == "connect device1", argv

          with subtest("an explicit pin is not overridden"):
              as_tester("bitbang serve shell -pin 4242")
              argv = report()["ARGV"]
              assert "-pin 4242" in argv, argv
              assert argv.count("-pin") == 1, argv

          with subtest("teardown refuses paths outside its own run directory"):
              helper = machine.succeed(
                  "grep -o '/nix/store/[a-z0-9]*-bitbang-share/bin/bitbang-share' "
                  "$(which bitbang) | head -1"
              ).strip()
              machine.fail(f"{helper} teardown /etc")
              machine.succeed("test -d /etc")

          with subtest("a stale session directory can be cleaned up"):
              mp = machine.succeed(f"{helper} setup {SHARE} 0").strip()
              machine.succeed(f"mountpoint -q {mp}")
              machine.succeed(f"{helper} teardown {mp}")
              machine.fail(f"test -e {mp}")
        '';
      };
    };
}
