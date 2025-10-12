{
  flake.modules.nixos.tailscale = { pkgs, ... }: {
    services.tailscale.enable = true;
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    environment.systemPackages = [ pkgs.tailscale ];
  };
}
