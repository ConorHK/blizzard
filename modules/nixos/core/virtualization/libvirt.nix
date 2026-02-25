{
  flake.modules.nixos.libvirt = _: {
    virtualisation.libvirtd.enable = true;

    users.extraGroups.libvirtd.members = [ "goose" ];

    programs.virt-manager.enable = true;
  };
}
