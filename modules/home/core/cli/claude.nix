{ inputs, ... }:
{
  flake.modules.homeManager.claude =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
      home.packages = [ pkgs.claude-code ];
    };
}
