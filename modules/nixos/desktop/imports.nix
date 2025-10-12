{ config, ... }:
{
  flake.modules.nixos.desktop.imports = with config.flake.modules.nixos; [
    android
    auto-login
    bluetooth
    keyring
    plymouth
    sound
    users
    yubikey
  ];
}
