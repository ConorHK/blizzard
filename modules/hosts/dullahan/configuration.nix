{
  flake.modules.nixos."nixosConfigurations/dullahan" =
    { ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILckflL1zKiJOTmgA3E7uhn7+Em+Nv940moIIaN3opbd";

      networking.hostName = "dullahan";
      networking.ipv4.address = "192.168.0.183";

      security.sudo.wheelNeedsPassword = false;

      system = {
        stateVersion = "25.05";
      };
    };
}
