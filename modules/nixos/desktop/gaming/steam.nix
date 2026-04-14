{ inputs, ... }:
let
  flake.modules.nixos.gaming.imports = [
    gamemode
    gamescope
    gaming-kernel
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
      capSysNice = true;
      args = [
        "--rt"
        "--expose-wayland"
      ];
    };
  };

  gaming-kernel =
    { lib, pkgs, ... }:
    {
      nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.default ];

      boot = {
        kernelPackages = lib.mkForce pkgs.cachyosKernels.linuxPackages-cachyos-latest;

        # Relax hardening that conflicts with CachyOS kernel / sched-ext
        kernelParams = lib.mkAfter [
          "lockdown=none"
          "module.sig_enforce=0"
        ];
        kernel.sysctl = {
          "net.core.bpf_jit_enable" = lib.mkForce true;
          "kernel.unprivileged_bpf_disabled" = lib.mkForce 0;
        };
      };

      # sched-ext support for pluggable schedulers (e.g. scx_lavd for gaming)
      services.scx = {
        enable = true;
        scheduler = "scx_lavd";
      };
    };

  mangohud =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.mangohud
      ];
    };

  steam = {
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      gamescopeSession.enable = true;
      platformOptimizations.enable = true;
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
