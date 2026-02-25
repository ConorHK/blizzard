{ inputs, ... }:
{
  flake.overlays.default = final: _prev: {
    # Reference packages from the flake output, not from config
    # This avoids infinite recursion
    serve-here = inputs.self.packages.${final.system}.serve-here or null;
    wallpapers = inputs.self.packages.${final.system}.wallpapers or null;
    creeper = inputs.self.packages.${final.system}.creeper or null;
    zellij-autolock = inputs.self.packages.${final.system}.zellij-autolock or null;
  };
}
