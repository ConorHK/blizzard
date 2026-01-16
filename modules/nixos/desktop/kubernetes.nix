{
  flake.modules.nixos.kubernetes =
    { pkgs, ... }:
    {
      virtualisation.docker.enable = true;

      users.users.goose.extraGroups = [
        "libvirtd"
        "docker"
      ];

      environment.systemPackages = with pkgs; [
        dnsmasq
        minikube
        kubectl
      ];
    };
}
