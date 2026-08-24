{ lib, ... }:
{
  # Every peer must list every other peer.
  flake.lib.syncthingDevices = {
    abhartach = "6UC67WT-CMLMJIP-JA6Z2H2-2H2ICCF-N7VRJBY-4XOMVIO-A6E7TN4-JVSW4A4";
    dullahan = "LAIGIVW-EIN4X7E-NTWJJ7D-XE6UBDQ-LXALLB6-UR77FXM-JZJMQJ7-5TKPNAX";
    # Written by the `syncthing-key` agenix generator.
    leprechaun = lib.removeSuffix "\n" (builtins.readFile ../nixos/server/syncthing/device-id);
  };
}
