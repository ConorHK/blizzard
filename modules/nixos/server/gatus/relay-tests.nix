{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.gatus-relay = pkgs.testers.runNixOSTest {
        name = "gatus-relay";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.gatus-relay
          ];

          environment.systemPackages = [ pkgs.curl ];

          blizzard.gatusRelay = {
            topicFile = "/etc/alert-topic";
            window = 15;
          };

          systemd.services.target = {
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 9000 --bind 127.0.0.1";
          };

          services.gatus = {
            enable = true;
            # fake-ntfy holds 8080.
            settings.web.port = 8081;
            settings.endpoints =
              map
                (name: {
                  inherit name;
                  url = "http://127.0.0.1:9000/";
                  interval = "3s";
                  conditions = [ "[STATUS] == 200" ];
                  alerts = [ { type = "custom"; } ];
                })
                [
                  "alpha"
                  "beta"
                  "gamma"
                ];
          };
        };

        testScript = alertHelpers + ''
          def relay(body):
              return machine.succeed(
                  "curl -sS -o /dev/null -w '%{http_code}' "
                  f"--data-binary $'{body}' http://127.0.0.1:8099/"
              ).strip()


          start_recorder()
          machine.wait_for_unit("gatus-relay.service")
          machine.wait_for_unit("gatus.service")
          machine.wait_for_open_port(8099)

          with subtest("a host outage sends one message, not three"):
              machine.succeed("systemctl stop target.service")
              [down] = wait_for_posts(1, timeout=60)
              assert down["title"] == "machine: 3 checks down", down
              assert down["message"] == "alpha, beta, gamma", down
              assert down["topic"] == "blizzard-test", down

          with subtest("recovery is reported once, as a batch"):
              machine.succeed("systemctl start target.service")
              recovered = wait_for_posts(2, timeout=60)[1]
              assert recovered["title"] == "machine: 3 checks recovered", recovered
              assert "white_check_mark" in recovered["tags"], recovered
              time.sleep(20)
              assert len(posts()) == 2, posts()

          with subtest("a lone failure names the check and its error"):
              assert relay("TRIGGERED\\nsolo\\nconnection refused") == "204"
              solo = wait_for_posts(3, timeout=30)[2]
              assert solo["title"] == "machine: solo down", solo
              assert solo["message"] == "connection refused", solo

          with subtest("garbage is rejected so gatus retries"):
              assert relay("bogus") == "400"

          with subtest("pending alerts survive a relay restart"):
              assert relay("RESOLVED\\nsolo\\n") == "204"
              machine.succeed("systemctl restart gatus-relay.service")
              machine.wait_for_open_port(8099)
              solo = wait_for_posts(4, timeout=30)[3]
              assert solo["title"] == "machine: solo recovered", solo
        '';
      };
    };
}
