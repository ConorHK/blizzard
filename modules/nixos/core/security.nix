{
  flake.modules.nixos.security =
    { lib, ... }:
    {
      security = {
        sudo = {
          wheelNeedsPassword = lib.mkDefault true;
          execWheelOnly = true;
        };
      };
    };
}
