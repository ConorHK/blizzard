{ inputs, ... }:
{
  flake.modules.nixos.quadlet =
    { pkgs, ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      services.userborn.enable = false;
      users.users = {
        containers = {
          isNormalUser = true;
          group = "containers";
          home = "/home/containers";
          createHome = true;
          autoSubUidGidRange = true;
          linger = true;
        };
        driver.extraGroups = [ "containers" ];
      };
      users.groups.containers = { };

      # A PAM session gets the activation the containers user's own XDG_RUNTIME_DIR,
      # so sd-switch reaches its bus and restarts changed containers. `%U` cannot be
      # used here: for a system unit it is always 0, regardless of User=.
      systemd.services.home-manager-containers.serviceConfig.PAMName = "systemd-user";

      environment.shellAliases = {
        podman-tui = "sudo -u containers XDG_RUNTIME_DIR=/run/user/$(id -u containers) /etc/profiles/per-user/containers/bin/podman-tui";
        asc = "sudo -u containers XDG_RUNTIME_DIR=/run/user/$(id -u containers)";
      };

      systemd.user.sockets.podman = {
        description = "Podman API Socket";
        listenStreams = [ "%t/podman/podman.sock" ];
        wantedBy = [ "sockets.target" ];
      };

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        sharedModules = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        users.containers.home = {
          stateVersion = "25.05";
          username = "containers";
          homeDirectory = "/home/containers";
          packages = [ pkgs.podman-tui ];
        };
      };
    };
}
