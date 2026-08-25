{
  config,
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      # No host imports zellij since the move to tmux, so evaluate it here to
      # keep the module (and the shared fish setting in core) from rotting.
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs.inputs = inputs;
        modules = [
          {
            home = {
              username = "goose";
              homeDirectory = "/home/goose";
              stateVersion = "25.05";
            };
            nix.package = pkgs.nix;
          }
          config.flake.modules.homeManager.core
          config.flake.modules.homeManager.zellij
        ];
      };
    in
    {
      checks.zellij =
        pkgs.runCommand "zellij"
          {
            nativeBuildInputs = [ pkgs.zellij ];
          }
          ''
            export HOME=$PWD
            ${pkgs.writeShellScript "check-zellij-config" (builtins.readFile ./check-config.sh)} \
              ${home.config.xdg.configFile."zellij/config.kdl".source}
            touch $out
          '';
    };
}
