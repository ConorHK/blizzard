{
  flake.modules.nixos."nixosConfigurations/bananach" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMum5X2fPLL5xXfKkpmJ9MtNwyhxqsgB72wcp8t+i4MR";

    networking.hostName = "bananach";

    services.uptime-kuma.settings.HOST = "100.96.40.127";

    system = {
      autoUpgrade.enable = true;
      stateVersion = "25.05";
    };
  };
}
