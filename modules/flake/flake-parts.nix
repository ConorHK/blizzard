{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.flake-parts.flakeModules.flakeModules
  ];
}
