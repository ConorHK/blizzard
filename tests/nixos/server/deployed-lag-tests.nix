{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.deployed-lag = pkgs.testers.runNixOSTest {
        name = "deployed-lag";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.deployed-lag
          ];

          blizzard.deployedLag.remote = "file:///srv/remote.git";
          # Only the test starts checks.
          systemd.timers.deployed-lag.wantedBy = pkgs.lib.mkForce [ ];
          environment.systemPackages = [ pkgs.git ];
        };

        testScript = alertHelpers + ''
          PENDING = "/var/lib/deployed-lag/pending"
          GIT = "git -c user.name=test -c user.email=test@example.com -C /root/work"


          def commit(message):
              machine.succeed(f"{GIT} commit -q --allow-empty -m {message}")
              machine.succeed(f"{GIT} push -q origin main")


          def promote():
              machine.succeed(f"{GIT} push -q origin main:deployed")


          def check():
              machine.succeed("systemctl start deployed-lag.service")


          start_recorder()
          machine.succeed(
              "git init -q --bare -b main /srv/remote.git",
              "git clone -q /srv/remote.git /root/work",
              "git -C /root/work symbolic-ref HEAD refs/heads/main",
          )
          commit("one")
          promote()

          with subtest("a promoted main stays quiet"):
              check()
              machine.fail(f"test -e {PENDING}")
              assert posts() == [], posts()

          with subtest("a fresh unpromoted commit only starts the clock"):
              commit("two")
              check()
              machine.succeed(f"test -e {PENDING}")
              assert posts() == [], posts()

          with subtest("a commit unpromoted past the threshold pages once"):
              machine.succeed(f"sed -i 's/ [0-9]*$/ 1000/' {PENDING}")
              check()
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Deploys stalled", alert
              assert alert["message"].startswith("CI has not promoted "), alert
              assert alert["priority"] == 4, alert
              commit("three")
              check()
              assert len(posts()) == 1, posts()

          with subtest("promotion clears the stall and says so"):
              promote()
              check()
              alert = wait_for_posts(2)[1]
              assert alert["title"] == "machine: Deploys resumed", alert
              assert alert["priority"] == 3, alert
              machine.fail(f"test -e {PENDING}")

          with subtest("a rewritten main commit re-arms instead of wedging"):
              commit("four")
              check()
              machine.succeed(f"test -e {PENDING}")
              machine.succeed(
                  f"{GIT} commit -q --amend --allow-empty -m four-again",
                  f"{GIT} push -q -f origin main",
              )
              promote()
              check()
              machine.fail(f"test -e {PENDING}")
              assert len(posts()) == 2, posts()

          with subtest("fetch failures page once on the third miss"):
              machine.succeed("mv /srv/remote.git /srv/gone.git")
              check()
              check()
              assert len(posts()) == 2, posts()
              check()
              alert = wait_for_posts(3)[2]
              assert alert["title"] == "machine: Deploy check blind", alert
              check()
              assert len(posts()) == 3, posts()
              machine.succeed("mv /srv/gone.git /srv/remote.git")
              check()
              alert = wait_for_posts(4)[3]
              assert alert["title"] == "machine: Deploy check back", alert
        '';
      };
    };
}
