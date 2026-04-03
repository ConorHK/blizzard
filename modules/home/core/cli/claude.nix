{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  flake.modules.homeManager.claude =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.claude-code ];
    };

  flake.modules.nixos.claude = {
    nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
  };
}
