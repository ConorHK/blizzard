{ config, ... }:
{
  flake.modules.nixos.desktop.imports = with config.flake.modules.nixos; [
    auto-login
    beeper
    bluetooth
    claude
    keyring
    sound
    users
    yubikey
  ];
}
