{ config, ... }:
{
  nixosHosts.banshee = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/banshee".imports = with config.flake.modules.nixos; [
    nixbuild
    pi-boot
    server-users
    sound
    spotifyd
    tts-web
  ];
}
