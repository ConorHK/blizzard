{
  flake.modules.nixos."nixosConfigurations/dullahan" =
    {
      config,
      lib,
      modulesPath,
      pkgs,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
        { config.facter.reportPath = ./facter.json; }
      ];

      services.xserver.xkb.layout = "gb";

      boot = {
        supportedFilesystems = lib.mkForce [ "btrfs" ];
        kernelPackages = pkgs.linuxPackages_latest;
      };

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
