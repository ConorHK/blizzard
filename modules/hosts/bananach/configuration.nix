{
  flake.modules.nixos."nixosConfigurations/bananach" = _: {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMum5X2fPLL5xXfKkpmJ9MtNwyhxqsgB72wcp8t+i4MR";

    networking.hostName = "bananach";

    services.gatus.settings.web.address = "100.96.40.127";
    programs.mosh.enable = false;

    # Reachable on tailscale0 only; the firewall stays shut on every other interface.
    services.openssh.openFirewall = false;

    system = {
      stateVersion = "25.05";
    };
  };
}
