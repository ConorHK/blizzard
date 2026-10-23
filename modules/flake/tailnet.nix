{ lib, ... }:
{
  options.flake.tailnetAddresses = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Tailnet IPv4 address of each server, by hostname.";
  };
}
