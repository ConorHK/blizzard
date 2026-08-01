{
  flake.modules.nixos.amdgpu =
    { pkgs, ... }:
    {
      # Enable the amdgpu "overdrive" interface so LACT can control fan
      # curves, undervolting, power limits and clocks. Without this bit
      # (0x4000) LACT can only monitor.
      boot.kernelParams = [ "amdgpu.ppfeaturemask=0xffffffff" ];

      hardware.graphics = {
        enable = true;
        extraPackages = [ pkgs.rocmPackages.clr.icd ];
      };

      environment.systemPackages = [
        pkgs.clinfo
        pkgs.lact
        pkgs.nvtopPackages.amd
      ];

      systemd.packages = [ pkgs.lact ];
      systemd.services.lactd.wantedBy = [ "multi-user.target" ];
    };
}
