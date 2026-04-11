{
  flake.modules.nixos."nixosConfigurations/bananach" =
    { lib, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMum5X2fPLL5xXfKkpmJ9MtNwyhxqsgB72wcp8t+i4MR";

      networking.hostName = "bananach";

      services.gatus.settings.web.address = "100.96.40.127";
      programs.mosh.enable = false;

      # Generate SSH host keys for agenix without running sshd or opening firewall ports
      services.openssh.openFirewall = false;
      systemd.services.sshd.wantedBy = lib.mkForce [ ];

      system = {
        stateVersion = "25.05";
      };
    };
}
