_: {
  flake.modules.nixos.snoop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      containersUid = toString config.users.users.containers.uid;

      command = pkgs.writeShellApplication {
        name = "snoop-command";
        runtimeInputs = [ pkgs.podman ];
        text = builtins.readFile ./snoop-command.sh;
      };
      podman-ro = pkgs.writeShellScriptBin "podman-ro" ''
        cd /
        exec ${pkgs.util-linux}/bin/runuser -u containers -- \
          ${pkgs.coreutils}/bin/env -i \
          XDG_RUNTIME_DIR=/run/user/${containersUid} HOME=/home/containers \
          ${lib.getExe command} "$@"
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
