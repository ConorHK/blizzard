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
        gnome = {
          # programs.ssh.startAgent is already providing an SSH agent
          gcr-ssh-agent.enable = false;
        };
        udisks2.enable = true;
      };
    };
}
