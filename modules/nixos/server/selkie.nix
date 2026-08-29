topLevel: {
  flake.modules.nixos.selkie =
    { config, inputs, ... }:
    let
      dataDir = "/storage/data/selkie";
      hostAddress = "10.111.0.1";
      # Restic reads the home as the host's `containers` user.
      uid = 1001;
      gid = 987;
    in
    {
      users = {
        users.containers.uid = uid;
        groups.containers.gid = gid;
      };

      systemd.tmpfiles.rules = [ "d ${dataDir} 0700 containers containers -" ];

      networking.nat = {
        enable = true;
        internalInterfaces = [ "ve-selkie" ];
      };

      restic.paths = [ dataDir ];

      containers.selkie = {
        autoStart = true;
        privateNetwork = true;
        # tailscaled needs /dev/net/tun and NET_ADMIN.
        enableTun = true;
        localAddress = "10.111.0.2";
        inherit hostAddress;

        specialArgs = { inherit inputs; };

        # bitbang's file share mounts bindfs; nspawn omits /dev/fuse.
        allowedDevices = [
          {
            node = "/dev/fuse";
            modifier = "rwm";
          }
        ];

        bindMounts = {
          "/home/goose" = {
            hostPath = dataDir;
            isReadOnly = false;
          };
          "/dev/fuse" = {
            hostPath = "/dev/fuse";
            isReadOnly = false;
          };
        };

        config =
          { pkgs, ... }:
          {
            imports = [
              inputs.home-manager.nixosModules.home-manager
            ]
            ++ (with topLevel.config.flake.modules.nixos; [
              bitbang
              claude
              clip
              ssh
              tailscale
            ]);

            blizzard.bitbang.shareMembers = [ "goose" ];

            networking.defaultGateway = {
              address = hostAddress;
              interface = "eth0";
            };

            nixpkgs = {
              overlays = [ inputs.crash.overlays.default ];
              config.allowUnfreePredicate = topLevel.config.flake.lib.allowUnfreePredicate;
            };

            # The host's daemon socket is bind-mounted in read-only.
            systemd = {
              services.nix-daemon.enable = false;
              sockets.nix-daemon.enable = false;
            };
            nix.settings.experimental-features = "nix-command flakes pipe-operators";

            users = {
              mutableUsers = false;
              defaultUserShell = pkgs.crash;
              users.goose = {
                isNormalUser = true;
                inherit uid;
                group = "goose";
                extraGroups = [ "wheel" ];
                openssh.authorizedKeys.keys = config.blizzard.sshKeys;
              };
              groups.goose.gid = gid;
            };

            # Key-only login, so there is no password to sudo with.
            security.sudo.wheelNeedsPassword = false;

            environment.systemPackages = [ pkgs.vim ];

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.goose.imports = with topLevel.config.flake.modules.homeManager; [
                cnvim
                core
                ssh
                zellij
              ];
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
