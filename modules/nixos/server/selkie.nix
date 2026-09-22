topLevel: {
  flake.modules.nixos.selkie =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      dataDir = "${config.blizzard.storage.data}/selkie";
      hostAddress = "10.111.0.1";
      hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL70IYhLosuJQKeTdA2tYRIUjCgcRGcQXAD3oyq7Wz+p";
      # Keep existing on-disk home ownership.
      uid = 1001;
      gid = 987;
    in
    {
      users = {
        users.containers.uid = uid;
        groups.containers.gid = gid;
        users.selkie-nix = {
          isSystemUser = true;
          group = "selkie-nix";
        };
        groups.selkie-nix = { };
      };

      assertions = [
        {
          assertion =
            lib.intersectLists [ "selkie-nix" "@selkie-nix" "*" ] config.nix.settings.trusted-users == [ ];
          message = "Selkie's Nix proxy must remain untrusted.";
        }
      ];

      systemd = {
        sockets.selkie-nix = {
          wantedBy = [ "sockets.target" ];
          socketConfig = {
            ListenStream = "/run/selkie-nix/socket";
            SocketMode = "0666";
            DirectoryMode = "0755";
          };
        };
        services = {
          selkie-nix = {
            requires = [ "nix-daemon.socket" ];
            after = [ "nix-daemon.socket" ];
            serviceConfig = {
              User = "selkie-nix";
              Group = "selkie-nix";
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd /nix/var/nix/daemon-socket/socket";
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              RestrictAddressFamilies = [ "AF_UNIX" ];
            };
          };
          "container@selkie" = {
            requires = [ "selkie-nix.socket" ];
            after = [ "selkie-nix.socket" ];
          };
        };
        tmpfiles.rules = [ "d ${dataDir} 0700 containers containers -" ];
      };

      networking.nat = {
        enable = true;
        internalInterfaces = [ "ve-selkie" ];
      };

      restic.paths = [ dataDir ];

      containers.selkie = {
        autoStart = true;
        privateNetwork = true;
        privateUsers = 524288;
        tmpfs = [ "/nix/var/nix/daemon-socket" ];
        extraFlags = [
          "--private-users-ownership=auto"
          "--bind=${dataDir}:/home/goose:idmap"
          "--bind-ro=/run/selkie-nix/socket:/nix/var/nix/daemon-socket/socket"
        ];
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
              agenix
              bitbang
              claude
              clip
              pi
              ssh
              tailscale
            ]);

            blizzard.bitbang.shareMembers = [ "goose" ];

            age.rekey.hostPubkey = hostPubkey;

            networking = {
              hostName = "selkie";
              defaultGateway = {
                address = hostAddress;
                interface = "eth0";
              };
            };

            nixpkgs = {
              overlays = [ inputs.crash.overlays.default ];
              config.allowUnfreePredicate = topLevel.config.flake.lib.allowUnfreePredicate;
            };

            # The proxy connects as an untrusted user.
            systemd = {
              services.nix-daemon.enable = false;
              sockets.nix-daemon.enable = false;
            };
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
              "pipe-operators"
            ];

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
              users.goose = {
                imports = with topLevel.config.flake.modules.homeManager; [
                  agenix
                  cnvim
                  core
                  git-identity
                  ssh
                  zai
                  zellij
                ];
                age.rekey = {
                  localStorageDir = ../../../.secrets/homes/selkie;
                  inherit hostPubkey;
                };
              };
            };

            system.stateVersion = "25.05";
          };
      };
    };
}
