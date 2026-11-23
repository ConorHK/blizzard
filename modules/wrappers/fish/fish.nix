topLevel@{ inputs, ... }:
{
  flake.wrappers.fish =
    {
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

      configFile = pkgs.replaceVars ./config.fish {
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
    in
    {
      imports = [ wlib.modules.default ];
      package = pkgs.fish;
      # A login shell is started as "-fish", which only a binary wrapper passes on.
      wrapperImplementation = "binary";
      flags."--init-command" = "source ${configFile}";
      # What the aliases and the prompt call, for a host that has none of it.
      runtimePkgs = lib.attrValues wrapped ++ [
        pkgs.difftastic
        pkgs.duf
        pkgs.dust
        pkgs.eza
        pkgs.wget
      ];
    };
}
