{
  flake.modules.nixos.tailscale =
    { lib, pkgs, ... }:
    let
      # Keeps both login paths up; flip false in a second deploy, once sshd:2222 answers everywhere.
      tailscaleSsh = true;
    in
    {
      services.tailscale = {
        enable = true;
        extraSetFlags = [ "--ssh=${lib.boolToString tailscaleSsh}" ];
      };
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
      environment.systemPackages = [ pkgs.tailscale ];
    };
}
