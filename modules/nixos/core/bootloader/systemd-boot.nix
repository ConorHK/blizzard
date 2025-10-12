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
          configurationLimit = 20;
          editor = false;
        };
      };
    };
}
