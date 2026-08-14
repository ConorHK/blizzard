{ lib, ... }:
{
  options.flake.testSupport = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
    description = "Fixtures shared between VM tests.";
  };
}
