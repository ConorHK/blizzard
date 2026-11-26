{
  # Herdr glue any agent harness calls from its own hooks: Claude Code's settings and pi's extensions.
  flake.modules.homeManager.herdr =
    { pkgs, ... }:
    let
      # jj, hc and herdr-app come from the user's PATH, so they match the running versions.
      hook =
        name: runtimeInputs:
        pkgs.writeShellApplication {
          name = "herdr-${name}";
          inherit runtimeInputs;
          text = builtins.readFile ./agent-hooks/${name}.sh;
        };
    in
    {
      home.packages = [
        (hook "workspace-guard" [ pkgs.jq ])
        (hook "tab-name" [
          pkgs.jq
          pkgs.claude-code
        ])
      ];
    };
}
