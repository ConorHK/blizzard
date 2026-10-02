topLevel: {
  # sudo is wheel-only (execWheelOnly), so doas carries the one
  # privileged hop: root wrapper drops to the containers user.
  flake.lib.mkPodmanRo =
    pkgs: containersUid:
    pkgs.writeShellApplication {
      name = "podman-ro";
      runtimeInputs = [ pkgs.jq ];
      text = ''
        sub=''${1-}
        [ "$#" -gt 0 ] && shift

        # Podman accepts global flags after subcommands.
        case "$sub" in
          events) allowed="--filter --format --since --stream --until" ;;
          images) allowed="-a --all --digests -f --filter --format --no-trunc -q --quiet" ;;
          info | version) allowed="-f --format" ;;
          inspect) allowed="-s --size -t --type" ;;
          logs) allowed="-f --follow -n --names --since --tail -t --timestamps --until" ;;
          port) allowed="-a --all -l --latest" ;;
          ps) allowed="-a --all -f --filter --format -l --latest -n --last --no-trunc -q --quiet -s --size --sort" ;;
          stats) allowed="-a --all --format --no-reset --no-stream" ;;
          *)
            echo "read-only subcommands only" >&2
            exit 2
            ;;
        esac

        for arg in "$@"; do
          case "$arg" in
            -*)
              case " $allowed " in
                *" ''${arg%%=*} "*) ;;
                *)
                  echo "podman-ro: $sub does not allow $arg" >&2
                  exit 2
                  ;;
              esac
              ;;
          esac
        done

        cd /
        podman() {
          ${pkgs.util-linux}/bin/runuser -u containers -- \
            env -i XDG_RUNTIME_DIR=/run/user/${containersUid} HOME=/home/containers TERM="''${TERM-dumb}" \
            ${pkgs.podman}/bin/podman "$@"
        }

        # Env carries the agenix-loaded secrets.
        if [ "$sub" = inspect ]; then
          podman inspect "$@" | jq 'map(del(.Config.Env))'
        else
          podman "$sub" "$@"
        fi
      '';
    };

  flake.modules.nixos.snoop =
    { config, pkgs, ... }:
    let
      podman-ro = topLevel.config.flake.lib.mkPodmanRo pkgs (toString config.users.users.containers.uid);
    in
    {
      users.users.snoop = {
        isNormalUser = true;
        group = "snoop";
        # Journal holds the quadlet units' logs; podman reads go through
        # podman-ro. Everything else on the box stays out of reach.
        extraGroups = [ "systemd-journal" ];
        home = "/home/snoop";
        createHome = true;
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          "restrict,pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuXSyHG5xPVC9UTWt9yaqG5oATC4RFMOIyv0/+kxjoi snoop@leprechaun (ai read-only)"
        ];
      };
      users.groups.snoop = { };

      environment.systemPackages = [ podman-ro ];

      security.doas = {
        enable = true;
        extraRules = [
          {
            users = [ "snoop" ];
            runAs = "root";
            cmd = "/run/current-system/sw/bin/podman-ro";
            noPass = true;
          }
        ];
      };
    };
}
