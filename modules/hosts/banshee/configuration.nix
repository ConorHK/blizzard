{
  flake.modules.nixos."nixosConfigurations/banshee" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPUlTg74nm25tWwbdgnjQInLl7H52zsMUO/tbf8sMH1z";

    networking.hostName = "banshee";
    networking.ipv4.address = "192.168.0.252";

    system = {
      stateVersion = "25.05";
    };
  };
}
