{ inputs, ... }:
let
  flake.modules.nixos.gaming.imports = [
    gamemode
    gamescope
    mangohud
    steam
    inputs.nix-gaming.nixosModules.platformOptimizations
  ];

  gamemode = {
    programs.gamemode = {
      enable = true;
      enableRenice = true;
    };
  };

  gamescope = {
    programs.gamescope = {
      enable = true;
      capSysNice = false;
      args = [
        "--rt"
        "--expose-wayland"
      ];
    };
  };

  mangohud =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.mangohud
      ];
    };

  steam =
    { pkgs, ... }:
    {
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        gamescopeSession.enable = true;
        platformOptimizations.enable = true;
        # CEF GPU accel lags the in-game overlay under XWayland; render it on CPU
        package = pkgs.steam.override { extraArgs = "-cef-disable-gpu"; };
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "steam"
    "steam-original"
    "steam-unwrapped"
    "steam-run"
  ];
  inherit flake;
}
