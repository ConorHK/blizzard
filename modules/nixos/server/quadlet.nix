{ inputs, ... }:
{
  flake.modules.nixos.quadlet =
    { ... }:
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
