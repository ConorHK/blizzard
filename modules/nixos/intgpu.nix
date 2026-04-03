{
  flake.modules.nixos.intgpu =
    { pkgs, ... }:
    {
      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
          libva-vdpau-driver
          libvdpau-va-gl
        ];
      };

      environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
    };
}
