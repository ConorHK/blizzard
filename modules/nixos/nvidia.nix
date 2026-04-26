{
  nixpkgs.allowedUnfreePackagePrefixes = [
    "cuda"
    "nvidia"
    "libcu"
    "libnv"
    "libnpp"
  ];

  flake.modules.nixos.nvidia =
    { config, pkgs, ... }:
    {
      services.xserver.videoDrivers = [ "nvidia" ];

      boot.blacklistedKernelModules = [ "nouveau" ];
      boot.kernelModules = [
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
      ];

      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      };

      hardware.nvidia-container-toolkit.enable = true;

      environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];
    };
}
