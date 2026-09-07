{ inputs, ... }:
{
  flake.modules.nixos.core =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [ inputs.crash.overlays.default ];
      users.defaultUserShell = pkgs.crash;

      # Fish reports no cwd of its own, so kitty cannot follow ssh.
      environment.etc."fish/config.fish".text = ''
        if status is-interactive; and not set -q KITTY_INSTALLATION_DIR
          function __report_cwd --on-variable PWD
            if not set -q ZMX_SESSION
              printf '\e]7;kitty-shell-cwd://%s%s\a' $hostname $PWD
            end
          end
          __report_cwd
        end
      '';
    };
}
