{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      podman-ro = config.flake.lib.mkPodmanRo pkgs "1001";
    in
    {
      # Rejected calls exit 2 before runuser.
      checks.snoop-podman-ro = pkgs.runCommand "snoop-podman-ro" { } ''
        ro=${podman-ro}/bin/podman-ro

        expect() {
          want=$1
          shift
          code=0
          "$ro" "$@" >/dev/null 2>&1 || code=$?
          if [ "$want" = rejected ] && [ "$code" -ne 2 ]; then
            echo "not rejected (exit $code): $*"
            exit 1
          fi
          if [ "$want" = allowed ] && [ "$code" -eq 2 ]; then
            echo "rejected: $*"
            exit 1
          fi
        }

        expect rejected
        expect rejected exec foo sh
        expect rejected --runtime=/tmp/x info
        expect rejected info --runtime=/tmp/x
        expect rejected info --runtime /tmp/x
        expect rejected ps --root /tmp/x
        expect rejected inspect --format '{{.Config.Env}}' foo
        expect rejected logs --hooks-dir=/tmp foo
        expect rejected ps -- -a

        expect allowed ps -a
        expect allowed logs --tail 50 foo
        expect allowed logs --since=-1h foo
        expect allowed inspect foo
        expect allowed info --format json

        touch $out
      '';
    };
}
