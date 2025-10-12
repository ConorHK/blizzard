{
  flake.modules.nixos."nixosConfigurations/abhartach" =
    { ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBeGvQMzAFPToh87kRuK4ogdA3OCFXIiEPuohfcLPWx";

      networking.hostName = "abhartach";
      networking.ipv4.address = "192.168.0.58";

      security.sudo.wheelNeedsPassword = false;

      system = {
        autoUpgrade.enable = false;
        stateVersion = "25.05";
      };
    };
}
