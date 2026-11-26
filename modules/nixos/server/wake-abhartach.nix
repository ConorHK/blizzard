{
  flake.modules.nixos.wake-abhartach =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "wake-abhartach";
          runtimeInputs = [ pkgs.wakeonlan ];
          text = ''
            wakeonlan "$@" 74:56:3c:b6:f0:7e
          '';
        })
      ];
    };
}
