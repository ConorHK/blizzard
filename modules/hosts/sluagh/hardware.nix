{
  flake.modules.nixos."nixosConfigurations/sluagh" =
    {
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      boot.initrd.availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-intel" ];
      hardware.cpu.intel.updateMicrocode = true;

      # Torrent and media drive.
      fileSystems."/home/mustang/storage" = {
        device = "/dev/disk/by-uuid/52a2564f-a28f-421c-8c9c-95ffddafd041";
        fsType = "ext4";
        options = [ "nofail" ];
      };

      networking.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    };
}
