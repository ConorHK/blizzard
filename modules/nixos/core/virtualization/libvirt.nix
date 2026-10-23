{
  flake.modules.nixos.libvirt = _: {
    virtualisation.libvirtd.enable = true;

    users.extraGroups.libvirtd.members = [ "goose" ];

    programs.virt-manager.enable = true;

    # libvirtd pulls machined in before its socket.
    systemd.services.systemd-machined = {
      wants = [ "systemd-machined.socket" ];
      after = [ "systemd-machined.socket" ];
    };
  };
}
