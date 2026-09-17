_: {
  flake.modules.nixos.snoop =
    { config, pkgs, ... }:
    let
      containersUid = toString config.users.users.containers.uid;

      # sudo is wheel-only (execWheelOnly), so doas carries the one
      # privileged hop: root wrapper drops to the containers user.
      podman-ro = pkgs.writeShellScriptBin "podman-ro" ''
        case "''${1-}" in
          events|images|info|inspect|logs|port|ps|stats|version) ;;
          *) echo "read-only subcommands only" >&2; exit 2 ;;
        esac
        cd /
        exec ${pkgs.util-linux}/bin/runuser -u containers -- \
          env XDG_RUNTIME_DIR=/run/user/${containersUid} HOME=/home/containers \
          ${pkgs.podman}/bin/podman "$@"
      '';
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
