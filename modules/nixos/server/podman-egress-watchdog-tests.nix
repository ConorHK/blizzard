{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.podman-egress-watchdog = pkgs.testers.runNixOSTest {
        name = "podman-egress-watchdog";

        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              alertRecorder
              config.flake.modules.nixos.podman-egress-watchdog
            ];

            environment.systemPackages = with pkgs; [
              iproute2
              procps
              util-linux
            ];
          };

        # The fake stands in for aardvark-dns: a compiled sleeper whose
        # comm matches, run by systemd-run inside a throwaway netns.
        testScript =
          let
            fake = pkgs.runCommand "aardvark-fake" { nativeBuildInputs = [ pkgs.gcc ]; } ''
              mkdir -p $out/bin
              printf '#include <unistd.h>\nint main() { for (;;) pause(); }\n' > main.c
              cc -o $out/bin/aardvark-dns main.c
            '';
          in
          alertHelpers
          + ''
            start_recorder()

            with subtest("nothing to probe when no rootless containers run"):
                machine.succeed("systemctl start podman-egress-watchdog.service")
                assert len(posts()) == 0, posts()

            with subtest("a routeless netns fails the probe and pages once"):
                machine.succeed("systemd-run --unit=fake-aardvark unshare -n ${fake}/bin/aardvark-dns")
                machine.wait_until_succeeds("pgrep -x aardvark-dns")
                machine.fail("systemctl start podman-egress-watchdog.service")
                machine.succeed(
                    "journalctl -u podman-egress-watchdog.service -o cat"
                    " | grep -q 'egress FAILED'"
                )
                machine.succeed(
                    "journalctl -u podman-egress-watchdog.service -o cat"
                    " | grep -q -- '--- netns routes ---'"
                )
                alert = wait_for_posts(1)[0]
                assert alert["title"] == "machine: Podman egress down", alert
                assert alert["priority"] == 4, alert
                assert alert["tags"] == ["zap"], alert

            with subtest("repeated failures do not re-page"):
                machine.fail("systemctl start podman-egress-watchdog.service")
                assert len(posts()) == 1, posts()

            with subtest("no aardvark at all is not a failure"):
                machine.succeed("systemctl stop fake-aardvark.service")
                machine.succeed("systemctl start podman-egress-watchdog.service")
                assert len(posts()) == 1, posts()
                machine.succeed("test -e /var/lib/podman-egress-watchdog/broken")

            with subtest("recovery clears state and posts once"):
                machine.succeed(
                    "systemd-run --unit=fake-aardvark-ok"
                    " unshare -n ${pkgs.runtimeShell} -c '${pkgs.iproute2}/bin/ip link set lo up; exec ${fake}/bin/aardvark-dns'"
                )
                machine.wait_until_succeeds("pgrep -x aardvark-dns")
                machine.succeed("podman-egress-probe 127.0.0.1")
                alert = wait_for_posts(2)[1]
                assert alert["title"] == "machine: Podman egress back", alert
                assert alert["priority"] == 3, alert
                machine.fail("test -e /var/lib/podman-egress-watchdog/broken")

            with subtest("the probe timer is armed"):
                machine.wait_for_unit("podman-egress-watchdog.timer")
          '';
      };
    };
}
