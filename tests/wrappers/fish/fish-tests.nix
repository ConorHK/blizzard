{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      hosted = self'.packages.fish.wrap { extraConfig = "alias hosted true"; };
    in
    {
      # The build's PATH has none of these tools, so they all come from the wrapper.
      checks.fish = pkgs.runCommand "fish-test" { } ''
        export HOME=$TMPDIR TERM=xterm-256color
        ${lib.getExe hosted} --interactive --command '
          for name in gs ls fzf-file-widget fish_prompt z hosted
              functions --query $name; or exit 1
          end
          for name in bat git jj starship eza zoxide carapace
              command --query $name; or exit 1
          end
          test "$PAGER" = "bat --plain"; or exit 1
          fish_prompt | string length --quiet; or exit 1
        '
        # A script gets the variables, and none of the interactive setup.
        ${lib.getExe hosted} --command '
          test "$PAGER" = "bat --plain"; or exit 1
          not functions --query hosted
        '
        touch "$out"
      '';
    };
}
