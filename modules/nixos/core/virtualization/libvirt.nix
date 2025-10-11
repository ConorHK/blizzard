{
  flake.modules.nixos.libvirt =
    { pkgs, ... }:
    {
      virtualisation.libvirtd.enable = true;

      users.extraGroups.libvirtd.members = [ "goose" ];

      programs.virt-manager.enable = true;
    };
}
