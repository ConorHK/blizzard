{
  perSystem =
    { pkgs, ... }:
    {
      checks.metrics-rules =
        pkgs.runCommand "metrics-rules" { nativeBuildInputs = [ pkgs.prometheus.cli ]; }
          ''
            cp ${../../../../modules/nixos/server/metrics/rules.yml} rules.yml
            cp ${./rules-tests.yml} rules-tests.yml
            promtool check rules rules.yml
            promtool test rules rules-tests.yml
            touch $out
          '';
    };
}
