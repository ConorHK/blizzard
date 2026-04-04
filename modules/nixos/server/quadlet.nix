{ inputs, ... }:
{
  flake.modules.nixos.quadlet =
    { ... }:
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      users.users.containers = {
        isNormalUser = true;
        group = "containers";
        home = "/home/containers";
        createHome = true;
        subUidRanges = [
          {
            startUid = 200000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 200000;
            count = 65536;
          }
        ];
      };
      users.groups.containers = { };

      # NixOS does not auto-generate these from subUidRanges
      environment.etc = {
        "subuid".text = "containers:200000:65536\n";
        "subgid".text = "containers:200000:65536\n";
      };

      # Start user services without an active login session
      systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/containers" ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        sharedModules = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        users.containers.home = {
          stateVersion = "25.05";
          username = "containers";
          homeDirectory = "/home/containers";
        };
      };
    };
}
