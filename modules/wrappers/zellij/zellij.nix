topLevel@{ inputs, ... }:
{
  flake.wrappers.zellij =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];

      options.shell = lib.mkOption {
        type = lib.types.str;
        default = lib.getExe (topLevel.config.flake.wrappers.fish.wrap { inherit pkgs; });
        description = "The shell every pane starts, for a host whose fish has its own lines.";
      };

      config = {
        package = pkgs.zellij;
        env.ZELLIJ_CONFIG_FILE = "${pkgs.replaceVars ./config.kdl {
          autolock = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.zellij-autolock;
          inherit (config) shell;
        }}";
      };
    };
}
