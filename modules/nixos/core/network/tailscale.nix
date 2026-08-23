{
  flake.modules.nixos.tailscale =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # Bypasses sshd and PAM, so it sets no loginuid; kept only where sshd has no other route.
      options.blizzard.tailscaleSsh = lib.mkEnableOption "Tailscale SSH";

      config = {
        services.tailscale = {
          enable = true;
          extraSetFlags = [ "--ssh=${lib.boolToString config.blizzard.tailscaleSsh}" ];
        };
        networking.firewall.trustedInterfaces = [ "tailscale0" ];
        environment.systemPackages = [ pkgs.tailscale ];
      };
    };
}
