{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      # The build's PATH has none of these tools, so they all come from the wrapper.
      checks.fish = pkgs.runCommand "fish-test" { } ''
        export HOME=$TMPDIR TERM=xterm-256color
        ${lib.getExe self'.packages.fish} --interactive --command '
          for name in gs ls fzf-file-widget fish_prompt z
              functions --query $name; or exit 1
          end
          for name in bat git jj starship eza
              command --query $name; or exit 1
          end
          test "$PAGER" = "bat --plain"; or exit 1
          fish_prompt | string length --quiet; or exit 1
        '
        touch "$out"
      '';
    };
}
