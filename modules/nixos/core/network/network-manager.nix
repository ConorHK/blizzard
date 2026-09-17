{
  flake.modules.nixos.network-manager =
    { config, lib, ... }:
    let
      inherit (lib)
        attrNames
        filterAttrs
        ;
    in
    {
      networking.networkmanager.enable = true;

      # NetworkManager is the sole DHCP client. The facter-generated
      # hardware.nix sets `networking.useDHCP = true`, which would otherwise
      # also start dhcpcd; running both races for leases and lands two
      # addresses on one interface, breaking egress when the kernel's
      # preferred source isn't the one the router honors.
      networking.dhcpcd.enable = lib.mkForce false;

      users.extraGroups.networkmanager.members =
        config.users.users
        |> filterAttrs (_: user: user.isNormalUser && builtins.elem "wheel" user.extraGroups)
        |> attrNames;

      environment.shellAliases.wifi = "nmcli dev wifi show-password";
    };
}
