{
  flake.wrappers.jujutsu =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];

      options.extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "TOML read after the shared config, for one host's settings.";
      };

      config = {
        package = pkgs.jujutsu;
        # jj merges the files in order, so the host's file wins.
        env.JJ_CONFIG = "${./config.toml}:${pkgs.writeText "jj-host.toml" config.extraConfig}";
        runtimePkgs = [ pkgs.difftastic ];
      };
    };
}
