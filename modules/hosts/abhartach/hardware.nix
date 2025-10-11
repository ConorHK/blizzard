{
  flake.modules.nixos."nixosConfigurations/abhartach" =
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

      boot = {

        kernelParams = [
          # hibernate settings
          "resume_offset=533760"
          "acpi_osi=\"!Windows 2015\"" # see https://bbs.archlinux.org/viewtopic.php?pid=2227023
        ];
        resumeDevice = "/dev/disk/by-label/nixos";

        supportedFilesystems = lib.mkForce [ "btrfs" ];
        kernelPackages = pkgs.linuxPackages_latest;

        initrd = {
          availableKernelModules = [
            "ahci"
            "nvme"
            "sd_mod"
            "usbhid"
            "usb_storage"
            "xhci_pci"
          ];
        };
        extraModulePackages = [ ];
      };

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
