{ inputs, ... }:
{
  nixosHosts.banshee = {
    unstable = false;
  };

  flake.modules.nixos."nixosConfigurations/banshee".imports = with inputs.self.modules.nixos; [
    nixbuild
    pi-boot
    server-users
    sound
    spotifyd
    tts-web
  ];
}
