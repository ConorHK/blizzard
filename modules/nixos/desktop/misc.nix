{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      programs = {
        dconf.enable = true;
      };
      home-manager.sharedModules = [
        {
          home.packages = [
            pkgs.pwvucontrol
            pkgs.qpwgraph
            pkgs.wiremix
          ];
        }
      ];

      services = {
        fwupd.enable = true;
        udisks2.enable = true;
      };
    };
}
