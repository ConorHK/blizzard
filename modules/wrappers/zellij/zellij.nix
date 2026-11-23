{ inputs, ... }:
{
  flake.wrappers.zellij =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.zellij;
      env.ZELLIJ_CONFIG_FILE = "${pkgs.replaceVars ./config.kdl {
        autolock = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.zellij-autolock;
      }}";
      # config.kdl starts fish in every pane.
      runtimePkgs = [ pkgs.fish ];
    };
}
