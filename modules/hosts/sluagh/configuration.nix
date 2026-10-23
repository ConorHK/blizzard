{
  flake.modules.nixos."nixosConfigurations/sluagh" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Compose projects under ~/containers.
      projects = [
        "arr"
        "jellyfin"
      ];
      storage = "/home/mustang/storage";
    in
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG04znMML5+hR9nBLzipZN1vcevvzdR+cQT5bNKicGgM";

      networking = {
        hostName = "sluagh";
        # head -c4 /dev/urandom | od -A none -t x4
        hostId = "3bf41414";
      };

      boot = {
        supportedFilesystems = [ "zfs" ];
        # 3 GiB; containers need the rest.
        kernelParams = [ "zfs.zfs_arc_max=3221225472" ];
      };

      services = {
        zfs.autoScrub.enable = true;
        sanoid = {
          enable = true;
          datasets."rpool/home" = {
            autosnap = true;
            autoprune = true;
            hourly = 24;
            daily = 7;
            monthly = 3;
          };
        };
      };

      # Compose files and app state predate blizzard.
      users = {
        users.mustang = {
          isNormalUser = true;
          uid = 1000;
          group = "mustang";
          extraGroups = [ "docker" ];
          openssh.authorizedKeys.keys = config.blizzard.sshKeys;
        };
        groups.mustang.gid = 1000;
      };

      virtualisation.docker.enableOnBoot = lib.mkForce true;
      environment.systemPackages = [ pkgs.docker-compose ];

      systemd.services = lib.listToAttrs (
        map (project: {
          name = "compose-${project}";
          value = {
            after = [
              "docker.service"
              "network-online.target"
            ];
            requires = [ "docker.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            unitConfig = {
              RequiresMountsFor = storage;
              ConditionPathExists = "/home/mustang/containers/${project}";
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              WorkingDirectory = "/home/mustang/containers/${project}";
              ExecStart = "${lib.getExe pkgs.docker-compose} up -d --remove-orphans";
              ExecStop = "${lib.getExe pkgs.docker-compose} stop";
            };
          };
        }) projects
      );

      networking.firewall = {
        # Jellyfin uses host networking; Docker opens the rest.
        allowedTCPPorts = [ 8096 ];
        # Jellyfin discovery, host network.
        allowedUDPPorts = [
          1900
          7359
        ];
      };

      system.stateVersion = "26.11";
    };
}
