{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi.claudeBridge;
      settingsFormat = pkgs.formats.json { };
      pi-claude-bridge = pkgs.buildNpmPackage {
        pname = "pi-claude-bridge";
        version = "0.9.2";
        src = pkgs.fetchFromGitHub {
          owner = "elidickinson";
          repo = "pi-claude-bridge";
          rev = "b2e7255ece0b8bfd3a6429fd5c147fd59984c785";
          hash = "sha256-ri1KD0H5Nbt8lAMHbMLVf7dwaoHNbTJfhEuF4Y8lFF8=";
        };
        # Dev deps lack lockfile integrity; pi supplies peers.
        postPatch = ''
          ${lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > p.json && mv p.json package.json
          ${lib.getExe pkgs.jq} '.packages |= with_entries(select(.value.dev != true)) | del(.packages[""].devDependencies)' \
            package-lock.json > l.json && mv l.json package-lock.json
        '';
        npmDepsHash = "sha256-+SsnGYxkQ1Z1E5HNYTwr7tmXDqdj9rP6BbTDPafLKo8=";
        dontNpmBuild = true;
        npmFlags = [
          "--ignore-scripts"
          "--legacy-peer-deps"
        ];
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp -r package.json src node_modules $out/
          runHook postInstall
        '';
      };
      settingsFile = settingsFormat.generate "claude-bridge.json" cfg.settings;
    in
    {
      options.programs.pi.claudeBridge = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install pi-claude-bridge, Claude Code as a provider.";
        };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/claude-bridge.json.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi = {
          settings.packages = [ "${pi-claude-bridge}" ];
          claudeBridge.settings = {
            provider.pathToClaudeCodeExecutable = lib.getExe pkgs.claude-code;
            askClaude.enabled = lib.mkDefault false;
          };
        };
        # Writable copy: the bridge records its startup notice.
        home.activation.piClaudeBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run install -Dm644 ${settingsFile} ${config.home.homeDirectory}/.pi/agent/claude-bridge.json
        '';
      };
    };
}
