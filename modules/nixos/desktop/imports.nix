{ config, ... }:
{
  flake.modules.nixos.desktop.imports = with config.flake.modules.nixos; [
    android
    auto-login
    bluetooth
    display-manager
    keyring
    plymouth
    sound
    yubikey
  ];
}
