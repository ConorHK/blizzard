topLevel: {
  flake.wrappers.git =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      fzf = topLevel.config.flake.wrappers.fzf.wrap { inherit pkgs; };
      globalConfig = pkgs.writeText "gitconfig" ''
        ${builtins.readFile ./config}
        [core]
        	excludesFile = ${./ignore}

        ${config.extraConfig}
      '';
    in
    {
      imports = [ wlib.modules.default ];

      options.extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Lines added after the shared config, for one host's settings.";
      };

      config = {
        package = pkgs.git;
        env.GIT_CONFIG_GLOBAL = "${globalConfig}";
        runtimePkgs = [
          pkgs.git-lfs
          # The switch-branch alias must get the fzf that carries its options.
          {
            data = fzf;
            prefix = true;
          }
        ];
      };
    };
}
