topLevel@{ inputs, ... }:
{
  flake.wrappers.fish =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      wrapped = lib.mapAttrs (_: wrapper: wrapper.wrap { inherit pkgs; }) {
        inherit (topLevel.config.flake.wrappers)
          bat
          fzf
          git
          jujutsu
          ripgrep
          starship
          ;
      };

      nixIndex = inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-db;
      commandNotFound = pkgs.writeShellScript "command-not-found" ''
        source ${nixIndex}/etc/profile.d/command-not-found.sh
        command_not_found_handle "$@"
      '';

      shared = pkgs.replaceVars ./config.fish {
        inherit commandNotFound;
        inherit (wrapped) fzf;
        carapace = lib.getExe pkgs.carapace;
        eza = lib.getExe pkgs.eza;
        nixYourShell = lib.getExe pkgs.nix-your-shell;
        puffer = pkgs.fishPlugins.puffer.src;
        starship = lib.getExe wrapped.starship;
        starshipConfig = wrapped.starship.configDir;
        zoxide = lib.getExe pkgs.zoxide;
      };

      configFile =
        pkgs.runCommand "config.fish"
          {
            inherit (config) extraConfig;
            passAsFile = [ "extraConfig" ];
            nativeBuildInputs = [ pkgs.fish ];
          }
          ''
            cat ${shared} "$extraConfigPath" > $out
            # fish skips a whole file over one syntax error, which would leave a bare shell.
            HOME=$TMPDIR fish --no-execute $out
          '';
    in
    {
      imports = [ wlib.modules.default ];

      options.extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Lines interactive shells read after the shared config, for one host's settings.";
      };

      config = {
        package = pkgs.fish;
        # A login shell is started as "-fish", which only a binary wrapper passes on.
        wrapperImplementation = "binary";
        flags."--init-command" = "source ${configFile}";
        # What the aliases, the prompt and the completions call, for a host that has none of it.
        runtimePkgs = lib.attrValues wrapped ++ [
          pkgs.carapace
          pkgs.difftastic
          pkgs.duf
          pkgs.dust
          pkgs.eza
          pkgs.wget
          pkgs.zoxide
        ];
      };
    };
}
