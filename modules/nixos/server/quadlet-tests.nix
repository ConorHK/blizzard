{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      # Without the XDG_RUNTIME_DIR fix in quadlet.nix, home-manager's activation
      # cannot reach the containers user's bus: the generated unit changes but the
      # running container keeps the old definition, silently.
      checks.quadlet-switch = pkgs.testers.runNixOSTest {
        name = "quadlet-switch";

        nodes.machine =
          { pkgs, lib, ... }:
          let
            image = pkgs.dockerTools.buildImage {
              name = "demo";
              tag = "latest";
              copyToRoot = pkgs.buildEnv {
                name = "demo-root";
                paths = [ pkgs.coreutils ];
                pathsToLink = [ "/bin" ];
              };
              config.Cmd = [
                "/bin/sleep"
                "infinity"
              ];
            };

            container = marker: {
              image = "localhost/demo:latest";
              environments.MARKER = marker;
            };
          in
          {
            imports = with config.flake.modules.nixos; [
              podman
              quadlet
            ];

            virtualisation.diskSize = 4096;

            # Nothing pulls this in inside a test VM, and podman's user-level wait
            # polls it for 90s before every container start.
            systemd.targets.network-online.wantedBy = [ "multi-user.target" ];

            # quadlet.nix puts `driver` in the containers group; server-users defines it.
            users.users.driver = {
              isNormalUser = true;
              group = "driver";
            };
            users.groups.driver = { };

            home-manager.users.containers.virtualisation.quadlet.containers.demo.containerConfig =
              container "one";

            specialisation.changed.configuration = {
              home-manager.users.containers.virtualisation.quadlet.containers.demo.containerConfig = lib.mkForce (
                container "two"
              );
            };

            environment.etc."demo-image.tar".source = image;
          };

        testScript = ''
          def as_containers(command):
              return machine.succeed(
                  "su containers -s /bin/sh -c "
                  f"'XDG_RUNTIME_DIR=/run/user/$(id -u containers) {command}'"
              )


          def invocation():
              return as_containers(
                  "systemctl --user show demo.service -p InvocationID --value"
              ).strip()


          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("user@1000.service")
          as_containers("podman load -i /etc/demo-image.tar")

          with subtest("the container starts from its declared definition"):
              # Boot runs activation before the user manager exists; a deploy onto a
              # running system is the case that matters.
              machine.succeed("systemctl restart home-manager-containers.service")
              machine.wait_for_unit("demo.service", user="containers")
              unit = as_containers("systemctl --user cat demo.service")
              assert "MARKER=one" in unit, unit

          before = invocation()

          with subtest("switching to a changed definition restarts the container"):
              machine.succeed(
                  "/run/current-system/specialisation/changed/bin/switch-to-configuration switch"
              )
              machine.wait_for_unit("demo.service", user="containers")

              unit = as_containers("systemctl --user cat demo.service")
              assert "MARKER=two" in unit, unit

              after = invocation()
              assert after != before, f"container was not restarted ({after})"
        '';
      };
    };
}
