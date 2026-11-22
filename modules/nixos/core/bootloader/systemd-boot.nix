{
  flake.modules.nixos.systemd-boot =
    { inputs, ... }:
    {
      imports = [
        inputs.self.modules.nixos.efi
      ];
      boot.loader = {
        systemd-boot = {
          enable = true;
          # Every generation can add its own kernel and initrd to the 512M ESP.
          configurationLimit = 5;
          editor = false;
        };
      };
    };
}
